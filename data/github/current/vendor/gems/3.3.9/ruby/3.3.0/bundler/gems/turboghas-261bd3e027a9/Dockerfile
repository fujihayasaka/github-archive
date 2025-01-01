# syntax = docker/dockerfile:1.3-labs
FROM golang:1.23.2@sha256:a7f2fc9834049c1f5df787690026a53738e55fc097cd8a4a93faa3e06c67ee32 AS base

FROM base AS build
WORKDIR /src/
ENV GOBIN=/dist/bin CGO_ENABLED=0 GOCACHE=/tmp/gocache GOEXPERIMENT=loopvar
RUN --mount=target=/src,type=bind,source=. --mount=type=cache,target=/tmp/gocache go run github.com/simon-engledew/check-go-version
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

FROM scratch
LABEL org.opencontainers.image.source=https://github.com/github/turboghas/
COPY --from=build /dist/bin/ /usr/bin/
USER 65534:65534
ENTRYPOINT ["turboghas"]
