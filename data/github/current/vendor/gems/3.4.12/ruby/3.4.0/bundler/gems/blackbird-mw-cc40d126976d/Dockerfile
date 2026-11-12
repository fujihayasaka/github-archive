# syntax=docker/dockerfile:experimental

ARG BLACKBIRD_CLIB_IMAGE=ghcr.io/github/blackbird/blackbird:sha-612d904c

ARG FRONTEND_MODE=with-frontend
FROM ghcr.io/github/gh-base-image/gh-builder-focal:20250212-230608-gb375c4ef5@sha256:7871014e09615bbf9684820a1c33b7db9f31d731087650cc970fed2a62ddf9af as base

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
FROM ghcr.io/github/gh-base-image/gh-builder-focal:20250212-230608-gb375c4ef5@sha256:7871014e09615bbf9684820a1c33b7db9f31d731087650cc970fed2a62ddf9af as build-frontend

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
ENV NODE_VERSION=20.18.1
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
FROM ghcr.io/github/gh-base-image/gh-base-focal:20250210-144822-g9ed4ec84d@sha256:63212e6d0b1e71334f50b2e744a8c5d91dfa7d7c2f6d710c2221c46871c3ef37 as run-with-frontend

COPY --from=build-frontend /root/go/src/github.com/github/blackbird-mw/admin-frontend/dist /admin-frontend/dist

# Deployable artifact without frontend
FROM ghcr.io/github/gh-base-image/gh-base-focal:20250210-144822-g9ed4ec84d@sha256:63212e6d0b1e71334f50b2e744a8c5d91dfa7d7c2f6d710c2221c46871c3ef37 as run-without-frontend

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
