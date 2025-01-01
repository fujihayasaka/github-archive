# build stage
FROM ghcr.io/github/gh-base-image/gh-builder-focal:latest as builder

WORKDIR /build
COPY . .

# compile TMA service
RUN make bin/tma

# compile TMA transition service
RUN make bin/transition

# runtime
FROM ghcr.io/github/gh-base-image/gh-base-focal:latest as runtime

# Copy assets from build stage to our empty runtime container
COPY --from=builder /build/bin/tma /bin/tma
COPY --from=builder /build/bin/transition /bin/transition

# Port for trust-metadata-api server
EXPOSE 8080

# Run as the non-root user created in gh-base-image
USER ${USER}

# Set default command run when this container is started
CMD ["/bin/tma", "server", "--backend", "mysql"]
