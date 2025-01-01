FROM --platform=linux/amd64 golang:bullseye

RUN apt-get update && \
    apt-get -y install unzip

RUN curl -sL https://github.com/protocolbuffers/protobuf/releases/download/v27.5/protoc-27.5-linux-x86_64.zip -o /tmp/protoc.zip && \
    unzip /tmp/protoc.zip -d /tmp/protoc && \
    chmod -R go+rX /tmp/protoc && \
    mv /tmp/protoc/bin/protoc /usr/local/bin/protoc && \
    mv /tmp/protoc/include/google /usr/local/include/ && \
    rm -rf /tmp/protoc.zip /tmp/protoc

ENV GO111MODULE=on

# Squash a warning about world-writable dirs in PATH
RUN chmod o-w /go/bin /go/

RUN go install github.com/golang/protobuf/protoc-gen-go@v1.5.1
RUN go install github.com/twitchtv/twirp/protoc-gen-twirp@v7.1.0
RUN go install github.com/thesilentg/proto-to-insomnia/protoc-gen-insomniaenv@v0.0.0-20200401011255-77b99326e0a3

WORKDIR /go/src/github.com/github/secret-scanning-proto

ADD config/tools/generate-go/generate /go/src/github.com/github/secret-scanning-proto/generate
ADD _template/go /go/src/github.com/github/secret-scanning-proto/_template/go

ENTRYPOINT ["/go/src/github.com/github/secret-scanning-proto/generate"]
