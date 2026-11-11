FROM ghcr.io/github/gh-base-image/gh-builder-focal:latest AS base

RUN go install github.com/golang/protobuf/protoc-gen-go@v1.5.4
RUN go install github.com/twitchtv/twirp/protoc-gen-twirp@v8.1.3
RUN go install github.com/arthurnn/twirp-ruby/protoc-gen-twirp_ruby@v1.11.0

COPY protogen_in_container protogen_in_container

ENTRYPOINT [ "./protogen_in_container" ]
