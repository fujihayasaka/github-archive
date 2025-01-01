# syntax=docker/dockerfile:1
# This Dockerfile uses the pinned base image approach for reproducible and dependabot-able base images.
# See https://thehub.github.com/epd/engineering/dev-practicals/containers/container-development/staying-up-to-date/
# Note that ARGs are not yet supported by dependabot's docker support.

######################
# Builder Stage
######################
FROM ghcr.io/github/gh-base-image/go-builder-focal:20250128-230835-g1762b3344@sha256:ce0b2eb83e6f3431dee6a4a477e3c9ebab36cd33d588d952c037236d914f9d2b AS builder
WORKDIR /go/src/app
ARG SKAFFOLD_GO_GCFLAGS
ARG CODESPACES

# Download modules via secret-mounted .netrc on Codespaces.
# On Janky, skip downloading and use vendored modules from resolve-dependencies
ADD go.* /go/src/app/
ADD vendor* /go/src/app/vendor
ENV GOPROXY=https://goproxy.githubapp.com/mod,https://proxy.golang.org,direct
ENV GOPRIVATE=''
ENV GONOPROXY=''
ENV GONOSUMDB=github.com/github/*
RUN --mount=type=secret,id=netrc,dst=/root/.netrc test -d vendor/ || go mod download

# Add sources
ADD ./cmd /go/src/app/cmd
ADD ./internal /go/src/app/internal
ADD ./lib /go/src/app/lib
ARG BUILD_TAG=ci

# Build
RUN --mount=type=cache,target=/root/.cache/go-build,sharing=locked go build -gcflags="${SKAFFOLD_GO_GCFLAGS}" -tags="${BUILD_TAG}" -o /go/bin/app/ ./cmd/...

######################
# Base Runtime Stage
######################
FROM ghcr.io/github/gh-base-image/gh-base-focal:20250128-192755-g00ad860d4@sha256:c487f86a2032dfdcbc9229b04d18a1860f401e716419319cd990731f1f75b4d3
LABEL org.opencontainers.image.source=https://github.com/github/actions-usage-metrics
ENV GOTRACEBACK=single
ARG DEV=false

# Dev tools ONLY installed for dev (skaffold) builds
RUN if [ "$DEV" = "true" ]; then wget -q -O - https://aka.ms/InstallAzureCLIDeb | bash ; fi

COPY --from=builder /go/bin/app /

USER github
# entrypoint/cmd is set by k8s deployment