FROM ghcr.io/github/gh-base-image/gh-builder-focal:latest as base

ENV CGO_ENABLED=0
ENV GOBIN=/app/bin

WORKDIR /app

FROM base as build

ARG MODMODE=vendor
ENV MODMODE=${MODMODE}

# We passed pkg-mirror-host as a secret to the build but it is not sensitive data.
RUN --mount=type=secret,id=pkg-mirror-host,target=/etc/pkg_mirror_host.txt \
    # This conditional is necessary because the file will not exist in a Codespace.
    if [ -f /etc/pkg_mirror_host.txt ]; then cat /etc/pkg_mirror_host.txt >> /etc/apt/mirrorlist.txt; fi

### install mysql. only use for enterprise-schema-check and not propagated past the build layer
RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
  apt-get update \
  && apt-get install -y default-mysql-client

COPY . .

# modmode=vendor for ci and local docker build
RUN script/automation/set-modmode

# If a token was specified, store it in the gitconfig
ARG GITHUB_TOKEN
RUN script/automation/set-github-token "$GITHUB_TOKEN"

RUN make tools && make ci

### build the final container
FROM ghcr.io/github/gh-base-image/gh-base-focal:latest AS run

# We passed pkg-mirror-host as a secret to the build but it is not sensitive data.
RUN --mount=type=secret,id=pkg-mirror-host,target=/etc/pkg_mirror_host.txt \
    # This conditional is necessary because the file will not exist in a Codespace.
    if [ -f /etc/pkg_mirror_host.txt ]; then cat /etc/pkg_mirror_host.txt >> /etc/apt/mirrorlist.txt; fi

RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
  apt-get update && \
  apt-get install -y ca-certificates netcat-openbsd curl && \
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb

COPY --from=build /app/bin/ /app/bin/
COPY --from=build /app/config/databases.yml /app/config/databases.yml
COPY --from=build /app/config/databases-proxima.yml /app/config/databases-proxima.yml

# create file for liveness probe
RUN touch tmp/heartbeat
WORKDIR /app
EXPOSE 8080

# The container needs to be run as something other than root.
# This is part of a defense-in-depth strategy, where if a running container is compromised it's limited in what it can do.
# It's also part of industry best practice (https://github.com/docker/docker-bench-security/blob/ec3ddf2acd7ec071eb267372a9c6840a11764c1d/tests/4_container_images.sh#L12-L18)
# as well as something customers and auditors regularly ask about.
# `github` user is part of the `gh-base-image` that can be referenced with `${USER}` (https://github.com/github/gh-base-image/blob/444ff62574fab3789890b0bd269f98cfedc009e8/gh-base-bionic/gh-base-bionic.dockerfile#L72-L77)
USER ${USER}

ENTRYPOINT ["echo 'ERROR: specify ENTRYPOINT in deployments/<service>.yaml file or when manually running the docker image'; exit 1"]
