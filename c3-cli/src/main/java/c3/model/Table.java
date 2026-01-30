package ay.model;

import java.util.Map;


public record Table(
    String catalog,
    String schema,
    String table,
    String type,
    Long rowCount,
    Float ranking,
    Map<String, Float> columnRecords
) {

    @Override
    public String toString() {
        return "%s.%s.%s (rows: %d, rank: %s, columns: %s)".formatted(
            catalog == null ? "" : catalog,
            schema == null ? "" : schema,
            table == null ? "" : table,
            rowCount == null ? 0 : rowCount,
            ranking == null ? "N/A" : String.format("%.2f", ranking),
            columnRecords == null ? "{}" : columnRecords.toString()
        );
    }

    public static boolean isIgnored(Float rank) {
        return rank != null && rank.equals(ay.model.Rankings.IGNORED.getValue());
    }
}
