# syntax=docker/dockerfile:1.2
# If you're trying to build this locally, you'll need to run it like
#  DOCKER_BUILDKIT=1 docker build --secret id=netrc,src="$HOME/.netrc" .

# don't forget to keep this in sync with the 'run' container below
FROM ghcr.io/github/gh-base-image/go-builder-focal:20260218-111752-g7f264370f@sha256:fcae872ab71aead23a16bedc7be06090540313a0b4a1cb7c243b388c77633694 AS build

ENV GOPROXY="https://goproxy.githubapp.com/mod,https://proxy.golang.org,direct"
ENV GOPRIVATE=
ENV GONOPROXY=
ENV GONOSUMDB=github.com/github/*

WORKDIR /app
COPY . /app

RUN --mount=type=secret,id=netrc,dst=/root/.netrc \
    ./script/build

### build the final container
FROM ghcr.io/github/gh-base-image/gh-base-focal:20260213-041855-g3803993a9@sha256:ab7b4051efbfb483c26e5cbaafab46d4bc43e0f3f22e03da46722d409fe77815 AS run

LABEL org.opencontainers.image.source=https://github.com/github/dependency-snapshots-api

# Shared user and group for Moda and GHES/GHPI run images.
# Statically defined user ID for dependency-snapshots-api created in enterprise2/chroot-prepare-base.sh
# Follows precedent of other GitHub GHES/GHPI containers e.g. https://github.com/github/authzd/blob/master/Dockerfile.cibuild-bionic
RUN groupadd -g 650 dependency-snapshots-api && \
    useradd -r -u 650 -g dependency-snapshots-api dependency-snapshots-api


# We passed pkg-mirror-host as a secret to the build but it is not sensitive data.
RUN --mount=type=secret,id=pkg-mirror-host,target=/etc/pkg_mirror_host.txt \
    if [ -f /etc/pkg_mirror_host.txt ]; then cat /etc/pkg_mirror_host.txt >> /etc/apt/mirrorlist.txt; fi

RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy built files but they will be owned by DG API as opposed to ROOT
COPY --chown=dependency-snapshots-api:dependency-snapshots-api --from=build /app/bin /app/bin
COPY --from=build /app/migrations /app/migrations

WORKDIR /app
EXPOSE 9597

HEALTHCHECK --interval=5s --timeout=3s CMD curl http://localhost:9597/_ping || exit 1

USER dependency-snapshots-api

ENTRYPOINT ["./bin/ds-api", "--port", "9597"]

###############################################################
# RUN ENTERPRISE
###############################################################
FROM run AS run-enterprise

###############################################################
# RUN MODA
###############################################################
FROM run AS run-moda
