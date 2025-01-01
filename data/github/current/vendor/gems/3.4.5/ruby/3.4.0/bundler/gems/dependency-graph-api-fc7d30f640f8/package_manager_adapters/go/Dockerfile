# This file builds the Docker image for the "go" package manager adaptor.
# It is invoked by 'script/build go', and builds the image used by 'script/start go'.

### build (use Go toolchain to build the executable) -------------------

FROM ghcr.io/github/gh-base-image/go-builder-focal:20250304-230608-gdb548f850@sha256:03ec13b4aa1d36ad9f1b847944bcdb61e3df781f326c2c71629ac8328ac84891 AS build

ENV GOPROXY="https://goproxy.githubapp.com/mod,https://proxy.golang.org/,direct"
ENV GONOSUMDB="github.com/github/*"

WORKDIR /gopma

COPY go/ go/
COPY script/configure-goproxy go/

# TODO(adonovan): we should not be saving a test executable in production images.
# However, avoiding that requires a significant rethink of script/*.
RUN cd go && \
    ./configure-goproxy && \
    go build -o /gopma/gopma ./ecosystem/go/gopma && \
    go test -v -c -o /gopma/gopma.test ./ecosystem/go/gopma


### run (contains just the files needed at run-time) -------------------

# The docker build process will need access to the Developer VPN to load this.
FROM octofactory.githubapp.com/docker-remote/debian:buster AS run

WORKDIR /gopma

COPY --from=build /gopma/gopma /gopma/gopma.test /gopma/
COPY package_manager_adapters/go/wrapper ./

# Install signing key for HTTPS.
RUN apt-get update && apt-get install -y ca-certificates sudo git && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd -g 612 dependency-graph-api && \
    useradd -r -u 621 -g dependency-graph-api dependency-graph-api

ENTRYPOINT ["/usr/bin/sudo", "-u", "dependency-graph-api", "--preserve-env=PATH,SINK_PROXY_URL,FJORD_URL,API_URL,FAILBOT_HAYSTACK_URL", "./wrapper"]
