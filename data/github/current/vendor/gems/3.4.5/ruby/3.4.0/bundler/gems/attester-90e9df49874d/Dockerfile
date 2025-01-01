# This Dockerfile assumes that the project has been vendored before building.
# This is done by:
# - script/resolve-dependencies, for a Janky build, or
# - script/ghae-ci-docker-build, for a GHAE Actions build.

### Build/lint the server.
# (Built by "-docker-image"-suffixed Janky CI build in config/moda/deployment.yaml
# and by script/ghae-*-docker-build.)
# TODO: replace latest with a commit hash or tag, when Attester is for production use.
FROM ghcr.io/github/gh-base-image/gh-builder-focal:latest as build
WORKDIR /app
COPY . .
RUN make bin/attester
### Run the tests (used by script/cibuild).
RUN make test

### Build the final server image (used by script/ghae-ci-docker-build).
# TODO: replace latest with a commit hash or tag, when Attester is for production use.
FROM ghcr.io/github/gh-base-image/gh-base-focal:latest as run
WORKDIR /app
COPY --chown=github:github --from=build /app/bin/ /app/bin/
COPY certs /app/certs
EXPOSE 8080
USER github
ENTRYPOINT ["bin/attester", "server"]
