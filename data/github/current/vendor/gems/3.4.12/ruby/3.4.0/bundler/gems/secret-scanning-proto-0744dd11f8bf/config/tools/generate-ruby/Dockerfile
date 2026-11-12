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
curl -sL https://github.com/google/protobuf/releases/download/v3.15.6/protoc-3.15.6-linux-${PROTOC_ARCH}.zip -o /tmp/protoc.zip
unzip /tmp/protoc.zip -d /tmp/protoc
chmod -R go+rX /tmp/protoc
mv /tmp/protoc/bin/protoc /usr/local/bin/protoc
mv /tmp/protoc/include/google /usr/local/include/
rm -rf /tmp/protoc.zip /tmp/protoc
EOF

ENV GO111MODULE=on

# Squash a warning about world-writable dirs in PATH
RUN chmod o-w /go/bin /go/

RUN go install github.com/twitchtv/twirp-ruby/protoc-gen-twirp_ruby@v1.7.1

WORKDIR /go/src/github.com/github/secret-scanning-proto

ADD config/tools/generate-ruby/generate /go/src/github.com/github/secret-scanning-proto/generate
ADD _template/ruby /go/src/github.com/github/secret-scanning-proto/_template/ruby

ENTRYPOINT ["/go/src/github.com/github/secret-scanning-proto/generate"]
