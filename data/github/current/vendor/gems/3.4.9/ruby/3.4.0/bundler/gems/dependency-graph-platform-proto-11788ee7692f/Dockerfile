FROM ghcr.io/github/gh-base-image/gh-builder-focal:latest AS base

ENV GOPROXY=https://proxy.golang.org,direct
ENV GOSUMDB=sum.golang.org

RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.31.0
RUN go install github.com/twitchtv/twirp/protoc-gen-twirp@v8.1.3
RUN go install github.com/arthurnn/twirp-ruby/protoc-gen-twirp_ruby@v1.11.0

COPY entrypoint entrypoint

ENTRYPOINT [ "./entrypoint" ]
