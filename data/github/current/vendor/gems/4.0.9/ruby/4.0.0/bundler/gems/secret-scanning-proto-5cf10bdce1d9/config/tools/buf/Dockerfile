FROM ghcr.io/github/gh-base-image/go-builder-focal:20260312-202145-g1854114ba@sha256:bab03028c1e2f004e717da8dd369c149641b6c6ece6ff66b568ee5b8398e2e25

ARG BUF_VERSION=1.67.0
ARG BUF_SHA256=b8682c2ea6f377cf1441e4fbc54ed1ecccbb9f2d887560c4320cf7807f015519

RUN curl -fsSL "https://github.com/bufbuild/buf/releases/download/v${BUF_VERSION}/buf-Linux-x86_64.tar.gz" \
    -o /tmp/buf.tar.gz && \
    echo "${BUF_SHA256}  /tmp/buf.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/buf.tar.gz -C /usr/local/bin --strip-components 2 && \
    rm /tmp/buf.tar.gz && \
    git config --global --add safe.directory /go/src/github.com/github/secret-scanning-proto

WORKDIR /go/src/github.com/github/secret-scanning-proto

ADD config/tools/buf/buf.yaml /go/src/github.com/github/secret-scanning-proto/buf.yaml

ENTRYPOINT ["buf"]
