# This file builds the Docker image for the "go" package manager adaptor.
# It is invoked by 'script/build go', and builds the image used by 'script/start go'.

### build (use Go toolchain to build the executable) -------------------

FROM ghcr.io/github/gh-base-image/go-builder-noble:20260415-201534-g088085f4b@sha256:2d4aa289dd6ffc83034f48c2650e80598b5a5664ef14df0b78c5325c2710ad20 AS build

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
FROM octofactory.githubapp.com/docker-remote/debian:bookworm@sha256:1d6cd964917a13b547d1ea392dff9a000c3f36070686ebc5c8755d53fb374435 AS run

WORKDIR /gopma

COPY --from=build /gopma/gopma /gopma/gopma.test /gopma/
COPY package_manager_adapters/go/wrapper ./

# Install signing key for HTTPS.
RUN apt-get update && apt-get install -y ca-certificates sudo git && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd -g 612 dependency-graph-api && \
    useradd -r -u 621 -g dependency-graph-api dependency-graph-api

ENTRYPOINT ["/usr/bin/sudo", "-u", "dependency-graph-api", "--preserve-env=PATH,SINK_PROXY_URL,FJORD_URL,API_URL,FAILBOT_HAYSTACK_URL", "./wrapper"]
