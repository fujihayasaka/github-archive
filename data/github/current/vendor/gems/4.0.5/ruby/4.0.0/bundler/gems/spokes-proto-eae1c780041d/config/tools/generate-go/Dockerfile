FROM ghcr.io/github/gh-base-image/go-builder-focal:latest

ENV GOBIN=/go/bin
ENV GOPATH=/go
ENV PATH=${GOBIN}:${PATH}

COPY config/tools/shared/install-protoc /opt/tools/install-protoc
RUN chmod +x /opt/tools/install-protoc && /opt/tools/install-protoc

ENV GO111MODULE=on

RUN go install github.com/golang/protobuf/protoc-gen-go@v1.5.2
RUN go install github.com/twitchtv/twirp/protoc-gen-twirp@v8.1.2

ARG GITHUB_TOKEN
ENV GOPROXY=https://nobody:${GITHUB_TOKEN}@goproxy.githubapp.com/mod,https://proxy.golang.org,direct
ENV GOPRIVATE=
ENV GONOPROXY=
ENV GONOSUMDB="github.com/github/*"
RUN go install github.com/github/protoc-gen-spokes-api-base/cmd/protoc-gen-spokes-api-base@0ba15d398eb6079575dc7702397a5f921cec7d06

WORKDIR /go/src/github.com/github/spokes-proto

ADD config/tools/generate-go/generate /go/src/github.com/github/spokes-proto/generate

ENTRYPOINT ["/go/src/github.com/github/spokes-proto/generate"]
