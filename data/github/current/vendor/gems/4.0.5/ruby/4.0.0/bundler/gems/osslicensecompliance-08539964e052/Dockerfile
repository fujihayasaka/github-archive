# This Dockerfile assumes that the project has been vendored before building.
# This is done by:
# - script/resolve-dependencies

FROM ghcr.io/github/gh-base-image/go-builder-noble:20260514-213008-g767294d5c as build
WORKDIR /app
COPY . .
RUN make build

FROM ghcr.io/github/gh-base-image/gh-base-noble:20260515-001154-ge5c1ce65a as run
WORKDIR /app
COPY --chown=github:github --from=build /app/bin/ /app/bin/
EXPOSE 8080
USER github
ENTRYPOINT ["bin/twirp"]
