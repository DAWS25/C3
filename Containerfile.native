# docker build --no-cache --progress=plain -f Containerfile -t ay:latest . 
# docker push ay:latest  

# BUILD STAGE

ARG UBI="public.ecr.aws/amazonlinux/amazonlinux:2023"
FROM ${UBI} AS build-stage

## As root
USER root
RUN bash -c "yum update -y \
    && yum -y groupinstall 'Development Tools'"

# MUSL
ARG MUST_URL="https://more.musl.cc/10/x86_64-linux-musl/x86_64-linux-musl-native.tgz"
RUN curl -L $MUST_URL | tar -xz -C /usr/local
ENV TOOLCHAIN_DIR="/usr/local/x86_64-linux-musl-native"
ENV PATH="/usr/local/x86_64-linux-musl-native/bin:${PATH}"

# ZLIB
ARG ZLIB_URL="https://zlib.net/zlib-1.3.1.tar.gz"
RUN curl -L $ZLIB_URL | tar -xz -C /usr/local

ENV CC="$TOOLCHAIN_DIR/bin/gcc"
RUN bash -c "cd /usr/local/zlib-1.3.1 && ./configure --prefix=$TOOLCHAIN_DIR --static && make  && make install"

# UPX
ARG UPX_URL="https://github.com/upx/upx/releases/download/v3.96/upx-3.96-amd64_linux.tar.xz"
RUN curl -L $UPX_URL | tar -xJ -C /usr/local
ENV PATH="/usr/local/upx-3.96-amd64_linux:${PATH}"
RUN upx --version

## GraalVM
ARG GRAALVM_URL="https://download.oracle.com/graalvm/25/latest/graalvm-jdk-25_linux-x64_bin.tar.gz"
RUN bash -c "curl -fsSL $GRAALVM_URL -o /tmp/graalvm.tar.gz \
    && mkdir -p /usr/local/graalvm \
    && tar -xzf /tmp/graalvm.tar.gz -C /usr/local/graalvm --strip-components=1 \
    && rm /tmp/graalvm.tar.gz" 

ENV JAVA_HOME="/usr/local/graalvm"
ENV PATH="$JAVA_HOME/bin:${PATH}"

## Copy source code
RUN mkdir -p "/usr/src"
WORKDIR "/usr/src"
COPY . .

# Build
RUN make

# RUNTIME STAGE
FROM scratch
COPY --from=build-stage "/usr/src/bin/entrypoint" "/entrypoint"
ENTRYPOINT ["/entrypoint"]
