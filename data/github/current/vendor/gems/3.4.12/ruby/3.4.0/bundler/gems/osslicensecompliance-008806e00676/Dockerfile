# This Dockerfile assumes that the project has been vendored before building.
# This is done by:
# - script/resolve-dependencies

FROM ghcr.io/github/gh-base-image/gh-builder-focal:20251119-090131-gb27dc275c as build
WORKDIR /app
COPY . .
RUN make build

FROM ghcr.io/github/gh-base-image/gh-base-focal:20251119-090131-gb27dc275c as run
WORKDIR /app
COPY --chown=github:github --from=build /app/bin/ /app/bin/
EXPOSE 8080
USER github
ENTRYPOINT ["bin/twirp"]
