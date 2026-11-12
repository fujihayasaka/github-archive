FROM golang:1.24-bookworm

RUN apt update && \
    apt -y install unzip

ARG TARGETARCH

RUN <<EOF
set -e
if [ "$TARGETARCH" = "arm64" ]; then
    PROTOC_ARCH="aarch_64";
else
    PROTOC_ARCH="x86_64";
fi
curl -sL https://github.com/protocolbuffers/protobuf/releases/download/v27.5/protoc-27.5-linux-${PROTOC_ARCH}.zip -o /tmp/protoc.zip
unzip /tmp/protoc.zip -d /tmp/protoc
chmod -R go+rX /tmp/protoc
mv /tmp/protoc/bin/protoc /usr/local/bin/protoc
mv /tmp/protoc/include/google /usr/local/include/
rm -rf /tmp/protoc.zip /tmp/protoc
EOF

# Squash a warning about world-writable dirs in PATH
RUN chmod o-w /go/bin /go/

RUN go install github.com/golang/protobuf/protoc-gen-go@v1.5.1
RUN go install github.com/verloop/twirpy/protoc-gen-twirpy@latest

WORKDIR /go/src/github.com/github/secret-scanning-proto

ADD config/tools/generate-python/generate /go/src/github.com/github/secret-scanning-proto/generate
ADD _template/python /go/src/github.com/github/secret-scanning-proto/_template/python

ENTRYPOINT ["/go/src/github.com/github/secret-scanning-proto/generate"]
