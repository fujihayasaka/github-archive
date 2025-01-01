FROM ghcr.io/github/gh-base-image/go-builder-focal:latest

COPY config/tools/shared/install-protoc /opt/tools/install-protoc
RUN chmod +x /opt/tools/install-protoc && /opt/tools/install-protoc

ENV GO111MODULE=on

RUN go install github.com/pseudomuto/protoc-gen-doc/cmd/protoc-gen-doc@v1.5.1

WORKDIR /go/src/github.com/github/spokes-proto

ADD config/tools/generate-docs/generate /go/src/github.com/github/spokes-proto/generate

ENTRYPOINT ["/go/src/github.com/github/spokes-proto/generate"]
