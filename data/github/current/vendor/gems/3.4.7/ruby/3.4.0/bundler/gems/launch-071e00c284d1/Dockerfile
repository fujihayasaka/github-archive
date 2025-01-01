# Builder image
FROM ghcr.io/github/gh-base-image/go-builder-focal:20250212-230609-gefca3d7a4 AS builder

ARG BUILD_SHA

ENV PATH $GOPATH/bin:$PATH

# Not sure if these are needed anymore, or need to change
WORKDIR /go/src/github.com/github/launch
ADD .   /go/src/github.com/github/launch

# Build
# This Dockerfile assumes that the project has been vendored before building.
# This is done by `script/resolve-dependencies` for a Janky build.
RUN script/build

# Make the final image
FROM ghcr.io/github/gh-base-image/gh-base-focal:20250210-144822-g9ed4ec84d AS run
# Default HTTP listener, likely for the GRPC shim.
ENV HTTP_ADDR=:6824
EXPOSE 6824

# For internal port if it needs to be different from default HTTP listener.
EXPOSE 6825

# Required labels
LABEL org.opencontainers.image.source=https://github.com/github/launch/

LABEL BUILD_SHA=${BUILD_SHA}

COPY --chown=github:github --from=builder /go/src/github.com/github/launch/migrations /migrations
COPY --chown=github:github --from=builder /go/src/github.com/github/launch/bin /bin
COPY --chown=github:github --from=builder /go/src/github.com/github/launch/config/security /etc/launch-chatops/security

# Create a non-root user
USER ${USER}
