# syntax = docker/dockerfile:1.3-labs
FROM golang:1.24.0@sha256:2b1cbf278ce05a2a310a3d695ebb176420117a8cfcfcc4e5e68a1bef5f6354da AS base

FROM base AS build
WORKDIR /src/
ENV GOBIN=/dist/bin CGO_ENABLED=0 GOCACHE=/tmp/gocache GOEXPERIMENT=loopvar
RUN --mount=target=/src,type=bind,source=. --mount=type=cache,target=/tmp/gocache go tool check-go-version
RUN --mount=target=/src,type=bind,source=. --mount=type=cache,target=/tmp/gocache go install ./cmd/...

FROM base AS tools
RUN apt-get update && apt-get install --no-install-recommends --yes busybox ruby-dev ruby cmake pkg-config libssl-dev
ARG PROTOBUF_VERSION=21.12
ARG SKEEMA_VERSION=1.4.2

RUN <<END
  set -eu
  case "$(dpkg --print-architecture)" in
    arm*) export PROTOBUF_ARCH=aarch_64; export SKEEMA_ARCH=arm64; ;;
    *)  export PROTOBUF_ARCH=x86_64; export SKEEMA_ARCH=amd64; ;;
  esac;
  busybox wget -q -O - "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOBUF_VERSION}/protoc-${PROTOBUF_VERSION}-linux-${PROTOBUF_ARCH}.zip" \
    | busybox unzip -d /usr -
  chmod +x /usr/bin/protoc
  busybox wget -q -O - "https://github.com/github/skeema/releases/download/v${SKEEMA_VERSION}-gh/skeema_${SKEEMA_VERSION}_linux_${SKEEMA_ARCH}.tar.gz" \
    | tar -xvpzC /usr/bin
END
COPY /schemas/ /work/schemas/

FROM ghcr.io/github/gh-base-image/gh-base-scratch@sha256:75fd63c272e97e397acc8aa771ac00642e41c6b89f3c9b395138903e4f34b074
LABEL org.opencontainers.image.source=https://github.com/github/turboghas/
COPY --from=build /dist/bin/ /usr/bin/
USER 65534:65534
ENTRYPOINT ["turboghas"]
