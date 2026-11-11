FROM ghcr.io/github/gh-base-image/go-builder-focal:latest

ENV GOBIN=/go/bin
ENV GOPATH=/go
ENV PATH=${GOBIN}:${PATH}

WORKDIR /go/src/github.com/github/spokes-proto/gen/go

ENV GO111MODULE=on

ADD gen/go .

RUN go mod vendor

ADD config/tools/test-go/test /go/src/github.com/github/spokes-proto/test

ADD _template/go .

ENTRYPOINT ["/go/src/github.com/github/spokes-proto/test"]
