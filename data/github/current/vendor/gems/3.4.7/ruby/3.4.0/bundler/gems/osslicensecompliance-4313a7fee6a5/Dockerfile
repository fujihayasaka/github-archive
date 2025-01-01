# This Dockerfile assumes that the project has been vendored before building.
# This is done by:
# - script/resolve-dependencies

FROM ghcr.io/github/gh-base-image/gh-builder-focal:20250725-230644-gc2200759f as build
WORKDIR /app
COPY . .
RUN make build

FROM ghcr.io/github/gh-base-image/gh-base-focal:20250711-165924-g6f92253c7 as run
WORKDIR /app
COPY --chown=github:github --from=build /app/bin/ /app/bin/
EXPOSE 8080
USER github
ENTRYPOINT ["bin/twirp"]
