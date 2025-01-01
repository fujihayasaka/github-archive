# syntax=docker/dockerfile:experimental

ARG BLACKBIRD_CLIB_IMAGE=ghcr.io/github/blackbird/blackbird:sha-69e051e7

ARG FRONTEND_MODE=with-frontend
FROM ghcr.io/github/gh-base-image/gh-builder-focal:20241008-231400-gb9e19cfd6@sha256:f15934696aed8bfcd07ab0eea648114872d9d0395686fd6b9c3b85b85b5d1d1e as base

WORKDIR /root/go/src/github.com/github/blackbird-mw

COPY ./script/install-tools script/install-tools

RUN ./script/install-tools

# Use a pre-built github/blackbird container to grab static clibs. See the
# README for instructions on updating. This MUST be pinned to a SHA and MUST
# match the Go package dependencies in go.mod:
#   - github.com/github/blackbird/crates/client
#   - github.com/github/blackbird/crates/core
FROM ${BLACKBIRD_CLIB_IMAGE} as blackbird

FROM base as build

# We passed pkg-mirror-host as a secret to the build but it is not sensitive data.
RUN --mount=type=secret,id=pkg-mirror-host,target=/etc/pkg_mirror_host.txt \
    # This conditional is necessary because the file will not exist for Build Pipelines jobs.
    if [ -f /etc/pkg_mirror_host.txt ]; then cat /etc/pkg_mirror_host.txt >> /etc/apt/mirrorlist.txt; fi

# Install libraries required for CGO bindings
RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    apt-get -qq update \
    && apt-get -qq install -y --no-install-recommends \
    libzstd-dev \
    && apt-get -qq clean -y \
    && apt-get -qq autoremove -y \
    && rm -rf /var/lib/apt/lists/*

COPY --from=blackbird /usr/local/lib/libblackbird_core.a /usr/local/lib/libblackbird_core.a
COPY --from=blackbird /usr/local/lib/libblackbird_client.a /usr/local/lib/libblackbird_client.a
COPY --from=blackbird /usr/local/lib/liblinguist.a /usr/local/lib/liblinguist.a

COPY . .

ENV CGO_LDFLAGS="-g -O2 -ldl -lm"
RUN go version \
    && go install ./...


# Build admin frontend
FROM ghcr.io/github/gh-base-image/gh-builder-focal:20241008-231400-gb9e19cfd6@sha256:f15934696aed8bfcd07ab0eea648114872d9d0395686fd6b9c3b85b85b5d1d1e as build-frontend

# We passed pkg-mirror-host as a secret to the build but it is not sensitive data.
RUN --mount=type=secret,id=pkg-mirror-host,target=/etc/pkg_mirror_host.txt \
    # This conditional is necessary because the file will not exist for Build Pipelines jobs.
    if [ -f /etc/pkg_mirror_host.txt ]; then cat /etc/pkg_mirror_host.txt >> /etc/apt/mirrorlist.txt; fi

# Install Node and Yarn
RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    apt-get -qq update \
    && apt-get -qq install -y --no-install-recommends \
    curl

RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

ENV NVM_DIR=/root/.nvm
ENV NODE_VERSION=18.0.0
RUN . "$NVM_DIR/nvm.sh" && nvm install ${NODE_VERSION}
RUN . "$NVM_DIR/nvm.sh" && nvm use v${NODE_VERSION}
RUN . "$NVM_DIR/nvm.sh" && nvm alias default v${NODE_VERSION}
ENV PATH="/root/.nvm/versions/node/v${NODE_VERSION}/bin/:${PATH}"
RUN npm install --global yarn

# Build admin frontend
WORKDIR /root/go/src/github.com/github/blackbird-mw
COPY . .

RUN cd admin-frontend && yarn install && yarn build


# Deployable artifact stage with frontend
FROM ghcr.io/github/gh-base-image/gh-base-focal:20241016-220333-g44b8ce0ff@sha256:a4de0b7756b7f66e7f41639441becc5214f21143331df97f159611690627d4a9 as run-with-frontend

COPY --from=build-frontend /root/go/src/github.com/github/blackbird-mw/admin-frontend/build /admin-frontend/build

# Deployable artifact without frontend
FROM ghcr.io/github/gh-base-image/gh-base-focal:20241016-220333-g44b8ce0ff@sha256:a4de0b7756b7f66e7f41639441becc5214f21143331df97f159611690627d4a9 as run-without-frontend

# Build the final image based on frontend mode
FROM run-${FRONTEND_MODE} as final

LABEL org.opencontainers.image.source="https://github.com/github/blackbird-mw"
USER github

# Copy over go binaries and config
COPY --from=build /root/go/bin/blackbird-* /
COPY --from=build --chown=github:github /root/go/src/github.com/github/blackbird-mw/config/blackbird/production/blackbird-client.toml /etc/blackbird/production/blackbird-client.toml
COPY --from=build --chown=github:github /root/go/src/github.com/github/blackbird-mw/config/blackbird/proxima/blackbird-client.toml /etc/blackbird/proxima/blackbird-client.toml

EXPOSE 8080

HEALTHCHECK --start-period=5s --interval=5s --timeout=1s --retries=10 \
  CMD curl --fail http://localhost:8080/ready || exit 1

CMD ["echo", "WARNING: An entrypoint for each binary must be set in its deployment YAML"]
