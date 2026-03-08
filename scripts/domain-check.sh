#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DIR/.." && pwd)"

OUT_FILE="${OUT_FILE:-$ROOT_DIR/scripts/available-domains.txt}"
LOG_FILE="${LOG_FILE:-$ROOT_DIR/scripts/domain-check.log}"
AVAILABLE_LOG_FILE="${AVAILABLE_LOG_FILE:-$ROOT_DIR/scripts/available-domains.log}"
WORKERS="${WORKERS:-40}"
TIMEOUT="${TIMEOUT:-8}"
RETRIES="${RETRIES:-3}"
START_TOKEN="aa00"
END_TOKEN="zz99"
SINGLE_DOMAIN=""
RESUME_FROM_LOG=1

usage() {
  cat <<'EOF'
Usage:
  scripts/domain-check.sh [options]

Options:
  --out <file>         Output file for available domains
  --log <file>         Log file (one line per lookup attempt)
  --available-log <f>  Log file for available domains only
  --workers <n>        Parallel workers (default: 40)
  --timeout <sec>      Curl max time per request (default: 8)
  --retries <n>        Retries for transient errors (default: 3)
  --from <aa00>        Start token, inclusive (default: aa00)
  --to <zz99>          End token, inclusive (default: zz99)
  --resume             Resume from last token found in log (default)
  --no-resume          Ignore log progress and start exactly from --from
  --single <domain>    Check one domain only (quick verification)
  -h, --help           Show help

Examples:
  scripts/domain-check.sh
  scripts/domain-check.sh --workers 80 --out /tmp/available.txt --log /tmp/domain-check.log
  scripts/domain-check.sh --single qx42.com
EOF
}

log_line() {
  local message="$1"
  printf '%s %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$message" >> "$LOG_FILE"
}

last_logged_token() {
  local token

  [[ -f "$LOG_FILE" ]] || return 1
  [[ -s "$LOG_FILE" ]] || return 1

  token=$(tail -n 5000 "$LOG_FILE" \
    | grep -Eo 'domain=[a-z]{2}[0-9]{2}\.com' \
    | tail -n1 \
    | sed -E 's/^domain=([a-z]{2}[0-9]{2})\.com$/\1/')

  [[ -n "$token" ]] || return 1
  echo "$token"
}

is_token() {
  [[ "$1" =~ ^[a-z]{2}[0-9]{2}$ ]]
}

token_to_num() {
  local token="$1"
  local a b n
  a=$(printf '%d' "'${token:0:1}")
  b=$(printf '%d' "'${token:1:1}")
  n=$((10#${token:2:2}))
  echo $((((a - 97) * 26 + (b - 97)) * 100 + n))
}

num_to_token() {
  local idx="$1"
  local letters num a b first second
  letters=$((idx / 100))
  num=$((idx % 100))
  a=$((letters / 26))
  b=$((letters % 26))
  printf -v first '%b' "\\$(printf '%03o' "$((97 + a))")"
  printf -v second '%b' "\\$(printf '%03o' "$((97 + b))")"
  printf "%s%s%02d" "$first" "$second" "$num"
}

check_domain() {
  local domain="$1"
  local domain_uc
  local attempt=1

  # Verisign is authoritative for .com RDAP, so use it directly.
  domain_uc=$(printf '%s' "$domain" | tr '[:lower:]' '[:upper:]')

  while (( attempt <= RETRIES )); do
    local response body status
    response=$(curl -sS --max-time "$TIMEOUT" -w $'\n%{http_code}' "https://rdap.verisign.com/com/v1/domain/${domain_uc}" || true)
    status=$(printf '%s\n' "$response" | tail -n1)
    body=$(printf '%s\n' "$response" | sed '$d')
    log_line "domain=${domain} attempt=${attempt} status=${status}"

    if [[ "$status" == "200" ]]; then
      log_line "domain=${domain} result=TAKEN"
      echo "TAKEN $domain"
      return 0
    fi

    if [[ "$status" == "404" ]]; then
      log_line "domain=${domain} result=AVAILABLE"
      printf '%s domain=%s result=AVAILABLE\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$domain" >> "$AVAILABLE_LOG_FILE"
      echo "AVAILABLE $domain"
      return 0
    fi

    if printf '%s' "$body" | grep -Eqi 'not found|no match|domain.*not.*found|object does not exist|no entries found'; then
      log_line "domain=${domain} result=AVAILABLE"
      printf '%s domain=%s result=AVAILABLE\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$domain" >> "$AVAILABLE_LOG_FILE"
      echo "AVAILABLE $domain"
      return 0
    fi

    if [[ "$status" =~ ^(429|5[0-9][0-9]|000)$ ]]; then
      sleep "$attempt"
      attempt=$((attempt + 1))
      continue
    fi

    break
  done

  log_line "domain=${domain} result=UNKNOWN"
  echo "UNKNOWN $domain"
  return 0
}

if [[ "${1:-}" == "__check_one" ]]; then
  check_domain "$2"
  exit 0
fi

while (($#)); do
  case "$1" in
    --out)
      OUT_FILE="$2"
      shift 2
      ;;
    --workers)
      WORKERS="$2"
      shift 2
      ;;
    --log)
      LOG_FILE="$2"
      shift 2
      ;;
    --available-log)
      AVAILABLE_LOG_FILE="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --retries)
      RETRIES="$2"
      shift 2
      ;;
    --from)
      START_TOKEN="$2"
      shift 2
      ;;
    --to)
      END_TOKEN="$2"
      shift 2
      ;;
    --single)
      SINGLE_DOMAIN="$2"
      shift 2
      ;;
    --resume)
      RESUME_FROM_LOG=1
      shift
      ;;
    --no-resume)
      RESUME_FROM_LOG=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "$SINGLE_DOMAIN" ]]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  mkdir -p "$(dirname "$AVAILABLE_LOG_FILE")"
  check_domain "$SINGLE_DOMAIN"
  exit 0
fi

if ! is_token "$START_TOKEN" || ! is_token "$END_TOKEN"; then
  echo "--from/--to must be in format [a-z][a-z][0-9][0-9], e.g. aa00" >&2
  exit 1
fi

start_idx=$(token_to_num "$START_TOKEN")
end_idx=$(token_to_num "$END_TOKEN")

if (( start_idx > end_idx )); then
  echo "--from must be <= --to" >&2
  exit 1
fi

if (( RESUME_FROM_LOG == 1 )); then
  if last_token=$(last_logged_token); then
    last_idx=$(token_to_num "$last_token")
    if (( last_idx >= start_idx && last_idx < end_idx )); then
      start_idx=$((last_idx + 1))
      START_TOKEN=$(num_to_token "$start_idx")
      echo "Resuming from log tail: last=${last_token}.com, next=${START_TOKEN}.com"
    elif (( last_idx >= end_idx )); then
      echo "Range already completed according to log tail (last=${last_token}.com). Nothing to do."
      exit 0
    fi
  fi
fi

tmp_results=$(mktemp)
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$AVAILABLE_LOG_FILE")"
touch "$LOG_FILE"
touch "$AVAILABLE_LOG_FILE"

tail -n 0 -f "$LOG_FILE" &
TAIL_PID=$!
cleanup() {
  rm -f "$tmp_results"
  if [[ -n "${TAIL_PID:-}" ]]; then
    kill "$TAIL_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "Checking domains from ${START_TOKEN}.com to ${END_TOKEN}.com"
echo "Workers: $WORKERS | Timeout: ${TIMEOUT}s | Retries: $RETRIES"
echo "Logging attempts to: $LOG_FILE"

export LOG_FILE AVAILABLE_LOG_FILE TIMEOUT RETRIES
for ((i=start_idx; i<=end_idx; i++)); do
  printf "%s.com\n" "$(num_to_token "$i")"
done | xargs -P "$WORKERS" -I{} "$0" __check_one {} > "$tmp_results"

awk '/^AVAILABLE / {print $2}' "$tmp_results" > "$OUT_FILE"

total=$(wc -l < "$tmp_results" | tr -d ' ')
available=$(wc -l < "$OUT_FILE" | tr -d ' ')
unknown=$(awk '/^UNKNOWN / {count++} END {print count+0}' "$tmp_results")

echo "Completed checks: $total"
echo "Available domains: $available"
echo "Unknown results: $unknown"
echo "Saved available domains to: $OUT_FILE"
echo "Saved available-domain log to: $AVAILABLE_LOG_FILE"
echo "Saved attempt log to: $LOG_FILE"
