# syntax = docker/dockerfile:1.2

# Production Dockerfile.
# In stage one, we build the code. We use a fixed image tag to ensure that our tools don't change underneath us.
FROM ghcr.io/github/gh-base-image/gh-base-focal:latest@sha256:713257ca15158248c8afb52c45a6d60f28a9ce69785c5c9c38ef0cf2e26c1a0a AS base
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    set -x && \
    apt-get update && \
    apt-get install --yes curl make git && \
    apt-get clean && \
    rm --recursive --force /var/lib/apt/lists/*

FROM base AS node
RUN --mount=type=cache,target=/var/cache/downloads \
    set -x && \
    eval 'download () { if ! echo "$1 $2" | sha256sum --check --status; then curl --location --fail --output "$2" "$3" && echo "$1 $2" | sha256sum --check --status; fi }' && \
    # node
    download eb5b031bdd728871c3b9a82655dbfa533bc262c0b6da1d09a86842430cef07d4 /var/cache/downloads/nodejs.tar.gz "https://nodejs.org/download/release/v20.18.2/node-v20.18.2-linux-x64.tar.gz" && \
    mkdir /usr/local/node && \
    tar --strip-components=1 -xf /var/cache/downloads/nodejs.tar.gz -C /usr/local/node

FROM base AS builder
COPY .go-version ./
RUN --mount=type=cache,target=/var/cache/downloads \
    set -x && \
    export GO_VERSION="$(cat .go-version | cut -d' ' -f1)" && \
    export GO_SHA256="$(cat .go-version | cut -d' ' -f2)" && \
    eval 'download () { if ! echo "$1 $2" | sha256sum --check --status; then curl --location --fail --output "$2" "$3" && echo "$1 $2" | sha256sum --check --status; fi }' && \
    # go
    download "${GO_SHA256}" /var/cache/downloads/go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" && \
    tar -xf /var/cache/downloads/go.tar.gz -C /usr/local/

ENV PATH="/usr/local/go/bin/:$PATH"

WORKDIR /app
COPY . .
RUN mkdir /app/bin
RUN make build-optimised -j4

# In stage two, we include the built binaries in a light(ish)-weight image.
FROM ghcr.io/github/gh-base-image/gh-base-focal:latest@sha256:713257ca15158248c8afb52c45a6d60f28a9ce69785c5c9c38ef0cf2e26c1a0a
LABEL org.opencontainers.image.source=https://github.com/github/turboscan/

COPY --from=builder /app/schemas/.skeema /app/schemas/.skeema
COPY --from=builder /app/rules/ /app/rules/
COPY --from=builder /app/migrations/ /app/migrations/
COPY --from=builder /app/bin/ /app/bin/
COPY --from=builder /app/script/istio-job-wrapper /app/script/istio-job-wrapper
# Autofix dependency
COPY --from=node /usr/local/node/ /usr/local/

WORKDIR /app/
EXPOSE 8888
RUN useradd --system --uid 641 --user-group turboscan
# create home folder
RUN mkdir /home/turboscan && chown -R turboscan:turboscan /home/turboscan

COPY --from=builder /app/ts/cocofix/javascript/ /app/ts/cocofix/javascript/

ENV PATH="/app/ts/cocofix/javascript/node_modules/.bin/:$PATH"
# Install cocofix
RUN --mount=type=secret,id=GH_TOKEN \
    cd /app/ts/cocofix/javascript/ && \
    NODE_ENV=production GITHUB_TOKEN="$(cat /run/secrets/GH_TOKEN)" npm install && \
    cocofix --version

RUN apt-get update && \
    apt-get install --yes curl && \
    apt-get clean && \
    rm --recursive --force /var/lib/apt/lists/*

USER turboscan
ENV MYSQL_SKEEMA_PATH=/app/schemas/.skeema
CMD ["/app/bin/turboscan", "service", "start", "turboscansvc"]
