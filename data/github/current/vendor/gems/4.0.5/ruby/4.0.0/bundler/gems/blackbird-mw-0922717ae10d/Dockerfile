# syntax=docker/dockerfile:experimental

ARG FRONTEND_MODE=with-frontend
ARG BLACKBIRD_BUILDER_IMAGE=ghcr.io/github/gh-base-image/gh-builder-focal:20250725-230644-gc2200759f@sha256:cdad63d2312e8ad1f889159a39985c7e8e43492a6c930a87d1123f12c3e02d18
ARG BLACKBIRD_CLIB_IMAGE=ghcr.io/github/blackbird/blackbird:sha-bd70dca9
ARG BLACKBIRD_IMAGE=ghcr.io/github/gh-base-image/gh-base-focal:20250929-093120-g65a62eb8c@sha256:ffbdcdf8a427a5f26bf5c7b28fa472a8ee93936078a237698c78a85526e71bb4

FROM ${BLACKBIRD_BUILDER_IMAGE} AS base

WORKDIR /root/go/src/github.com/github/blackbird-mw

COPY ./script/install-tools script/install-tools

RUN ./script/install-tools

# Use a pre-built github/blackbird container to grab static clibs. See the
# README for instructions on updating. This MUST be pinned to a SHA and MUST
# match the Go package dependencies in go.mod:
#   - github.com/github/blackbird/crates/client
#   - github.com/github/blackbird/crates/core
FROM ${BLACKBIRD_CLIB_IMAGE} AS blackbird

FROM base AS build

# We passed pkg-mirror-host as a secret to the build but it is not sensitive data.
RUN --mount=type=secret,id=pkg-mirror-host,target=/etc/pkg_mirror_host.txt \
    # This conditional is necessary because the file will not exist for Build Pipelines jobs.
    if [ -f /etc/pkg_mirror_host.txt ]; then cat /etc/pkg_mirror_host.txt >> /etc/apt/mirrorlist.txt; fi

# Install libraries required for CGO bindings
RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends libzstd-dev

COPY --from=blackbird /usr/local/lib/libblackbird_core.a /usr/local/lib/libblackbird_core.a
COPY --from=blackbird /usr/local/lib/libblackbird_client.a /usr/local/lib/libblackbird_client.a
COPY --from=blackbird /usr/local/lib/liblinguist.a /usr/local/lib/liblinguist.a

COPY . .

ENV CGO_LDFLAGS="-g -O2 -ldl -lm"
RUN go version \
    && go install ./...


# Build admin frontend
FROM ${BLACKBIRD_BUILDER_IMAGE} AS build-frontend


# We passed pkg-mirror-host as a secret to the build but it is not sensitive data.
RUN --mount=type=secret,id=pkg-mirror-host,target=/etc/pkg_mirror_host.txt \
    # This conditional is necessary because the file will not exist for Build Pipelines jobs.
    if [ -f /etc/pkg_mirror_host.txt ]; then cat /etc/pkg_mirror_host.txt >> /etc/apt/mirrorlist.txt; fi

# Install Node
RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get -qq update \
    && apt-get -qq install -y --no-install-recommends curl

RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

ENV NVM_DIR=/root/.nvm
ENV NODE_VERSION=20.19.0
RUN . "$NVM_DIR/nvm.sh" && nvm install ${NODE_VERSION}
RUN . "$NVM_DIR/nvm.sh" && nvm use v${NODE_VERSION}
RUN . "$NVM_DIR/nvm.sh" && nvm alias default v${NODE_VERSION}
ENV PATH="/root/.nvm/versions/node/v${NODE_VERSION}/bin/:${PATH}"

# Build admin frontend
WORKDIR /root/go/src/github.com/github/blackbird-mw
COPY . .

RUN cd admin-frontend && npm ci && npm run build


# Deployable artifact stage with frontend
FROM ${BLACKBIRD_IMAGE} AS run-with-frontend

COPY --from=build-frontend /root/go/src/github.com/github/blackbird-mw/admin-frontend/dist /admin-frontend/dist

# Deployable artifact without frontend
FROM ${BLACKBIRD_IMAGE} AS run-without-frontend

# Build the final image based on frontend mode
FROM run-${FRONTEND_MODE} AS final

# Install curl (for the healthcheck below)
USER root
RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends curl

LABEL org.opencontainers.image.source="https://github.com/github/blackbird-mw"
USER github

# Copy over go binaries and config
COPY --from=build /root/go/bin/blackbird-* /
COPY --from=build --chown=github:github /root/go/src/github.com/github/blackbird-mw/config/blackbird/production/blackbird-client.toml /etc/blackbird/production/blackbird-client.toml
COPY --from=build --chown=github:github /root/go/src/github.com/github/blackbird-mw/config/blackbird/proxima/blackbird-client.toml /etc/blackbird/proxima/blackbird-client.toml

EXPOSE 8080

HEALTHCHECK --start-period=30s --interval=5s --timeout=1s --retries=10 \
  CMD curl --fail http://localhost:8080/ready || exit 1

CMD ["echo", "WARNING: An entrypoint for each binary must be set in its deployment YAML"]
