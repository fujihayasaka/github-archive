# This Dockerfile assumes that the project has been vendored before building.
# This is done by:
# - script/resolve-dependencies

FROM ghcr.io/github/gh-base-image/gh-builder-focal:20260226-001000-g34cc69b0a as build
WORKDIR /app
COPY . .
RUN make build

FROM ghcr.io/github/gh-base-image/gh-base-focal:20260213-041855-g3803993a9 as run
WORKDIR /app
COPY --chown=github:github --from=build /app/bin/ /app/bin/
EXPOSE 8080
USER github
ENTRYPOINT ["bin/twirp"]
