FROM ghcr.io/github/gh-base-image/go-builder-focal:latest

ENV GOBIN=/go/bin
ENV GOPATH=/go
ENV PATH=${GOBIN}:${PATH}

COPY config/tools/shared/install-protoc /opt/tools/install-protoc
RUN chmod +x /opt/tools/install-protoc && /opt/tools/install-protoc

ENV GO111MODULE=on

RUN go install github.com/twitchtv/twirp-ruby/protoc-gen-twirp_ruby@v1.9.0

WORKDIR /go/src/github.com/github/spokes-proto

ADD config/tools/generate-ruby/generate /go/src/github.com/github/spokes-proto/generate

ENTRYPOINT ["/go/src/github.com/github/spokes-proto/generate"]
