# ===================================================================
# Main Docker image for production builds
# ===================================================================
FROM ghcr.io/github/gh-base-image/gh-builder-focal:latest AS builder

WORKDIR /app

ARG SKAFFOLD_GO_GCFLAGS

# Download modules via secret-mounted .netrc on Codespaces.
# On Janky, skip downloading and use vendored modules from resolve-dependencies
ADD go.* /app
ADD vendor* /app/vendor
ENV GOPROXY=https://goproxy.githubapp.com/mod,https://proxy.golang.org,direct
ENV GOPRIVATE=''
ENV GONOPROXY=''
ENV GONOSUMDB=github.com/github/*
RUN --mount=type=secret,id=netrc,dst=/root/.netrc test -d vendor/ || go mod download

# Copy rest of src and build into executables
ADD . /app/
RUN --mount=type=cache,target=/root/.cache/go-build,sharing=locked go build -gcflags="${SKAFFOLD_GO_GCFLAGS}" -o /app/bin/hosted-compute-ims-api ./cmd/twirp
RUN --mount=type=cache,target=/root/.cache/go-build,sharing=locked go build -gcflags="${SKAFFOLD_GO_GCFLAGS}" -o /app/bin/hosted-compute-ims-worker ./cmd/worker
RUN --mount=type=cache,target=/root/.cache/go-build,sharing=locked go build -gcflags="${SKAFFOLD_GO_GCFLAGS}" -o /app/bin/hosted-compute-ims-cronjobs ./cmd/cronjobs

# Prepare for running
FROM ghcr.io/github/gh-base-image/gh-fips-base-focal:latest
LABEL org.opencontainers.image.source=https://github.com/github/hosted-compute-ims
ENV GOTRACEBACK=single
ARG DEV=false

# Dev tools ONLY installed for dev (skaffold) builds
RUN if [ "$DEV" = "true" ]; then wget -q -O - https://aka.ms/InstallAzureCLIDeb | bash ; fi
COPY --from=builder /app/config/kustomize/devoverlays/*.yml /app/bin/config/
RUN if [ "$DEV" != "true" ]; then rm -rf /app/bin/config; fi

COPY --from=builder /app/config/oidc-issuers/* /app/bin/
COPY --from=builder /app/bin/*.pem /app/bin/
COPY --from=builder /app/bin/hosted-compute-ims-* /app/bin/
WORKDIR /app

USER github