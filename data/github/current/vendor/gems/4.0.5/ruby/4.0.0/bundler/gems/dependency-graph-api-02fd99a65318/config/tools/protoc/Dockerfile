FROM golang:1.22@sha256:1cf6c45ba39db9fd6db16922041d074a63c935556a05c5ccb62d181034df7f02

# Install base dependencies
RUN apt-get update && apt-get install -y unzip wget

# Set the working directory
WORKDIR /go/src/tools

ENV PROTOBUF_VERSION=21.12

# Download and unzip protoc
RUN wget "https://github.com/protocolbuffers/protobuf/releases/download/v$PROTOBUF_VERSION/protoc-$PROTOBUF_VERSION-linux-x86_64.zip" && \
  unzip "protoc-$PROTOBUF_VERSION-linux-x86_64.zip" -d "/protobuf" && \
  rm "protoc-$PROTOBUF_VERSION-linux-x86_64.zip"

# Initialize go module and install necessary packages
RUN go mod init tools && \
  go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.31.0 && \
  go install github.com/twitchtv/twirp/protoc-gen-twirp@v8.1.3 && \
  go install github.com/arthurnn/twirp-ruby/protoc-gen-twirp_ruby@v1.11.0

# Entrypoint runs protoc
ENTRYPOINT ["/protobuf/bin/protoc"]
