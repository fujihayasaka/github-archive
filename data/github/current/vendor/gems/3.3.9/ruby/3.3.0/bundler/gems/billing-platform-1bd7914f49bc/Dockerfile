# syntax=docker/dockerfile:experimental

# This Dockerfile needs access to goproxy
#
# Local development:
#   Add a file named .goproxytoken to the root of this repository with the contents of your GITHUB_TOKEN.
#   This token must, at a minimum, have `repo` and `read:packages` scopes.
#
# Codespaces development:
#   The contents of GITHUB_TOKEN are automatically written to .goproxytoken when the space is created.
#   This token has been properly configured for the correct scopes.
#
# Janky builds:
#   /script/resolve-dependencies creates .goproxytoken and .packagestoken automatically. This is the
#   only environment that needs two separate tokens.

### Base image
FROM ghcr.io/github/gh-base-image/go-builder-focal:20240516-230438-g8cad50cb4@sha256:8ac1a291d7b149655ee43edb45ca2ce46eeb18effb14be4e68de0f7920001526 as base
WORKDIR /app
COPY . .

# We passed pkg-mirror-host as a secret to the build but it is not sensitive data.
RUN --mount=type=secret,id=pkg-mirror-host,target=/etc/pkg_mirror_host.txt \
  # This conditional is necessary because the file will not exist for Build Pipelines jobs.
  if [ -f /etc/pkg_mirror_host.txt ]; then cat /etc/pkg_mirror_host.txt >> /etc/apt/mirrorlist.txt; fi

# Mounting the apt-auth-conf secret is necessary for reaching GitHub internal package registries through the Actions Network Gateway (ANG)
RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    echo "machine goproxy.githubapp.com login nobody password $(cat .goproxytoken)" > $HOME/.netrc \
    && apt update \
    && ./.devcontainer/scripts/install-ci-tools.sh \
    && go version

# Install dependencies for Change Feed Processor
RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
  apt update \
  && apt install -y gnupg
RUN curl -sSL https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
RUN line=`grep "DISTRIB_RELEASE" /etc/lsb-release` \
   && ver=`echo $line | cut -d'=' -f2` \
   && url="https://packages.microsoft.com/ubuntu/$ver/prod" \
   && echo deb [arch=amd64] $url focal main > /etc/apt/sources.list.d/microsoft-prod.list
RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
  apt update \
  && apt -y install dotnet-sdk-8.0

### Build the application
FROM base as build
RUN make build
RUN make publish-change-feed

### Run the tests
FROM build AS test
RUN make go-test

### Runtime image
FROM ghcr.io/github/gh-base-image/gh-fips-base-focal:20240628-210635-gf384d38c0@sha256:fbd17b964fb1b86774c3183a78110b25375d2deeef5b72d7df6bbfbe46834ebc

COPY --chown=github:github --from=build /app/bin/ /app/bin/
WORKDIR /app
EXPOSE 8989

USER github
ENTRYPOINT ["./bin/usage-ingestion"]
