FROM ghcr.io/github/gh-base-image/go-builder-focal:latest

ENV GO111MODULE=on

RUN go install github.com/bufbuild/buf/cmd/buf@v1.1.0 && \
    git config --global --add safe.directory /go/src/github.com/github/spokes-proto/.git

WORKDIR /go/src/github.com/github/spokes-proto

ADD config/tools/buf/buf.yaml /go/src/github.com/github/spokes-proto/buf.yaml

ENTRYPOINT ["buf"]
