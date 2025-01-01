# syntax=docker/dockerfile:experimental

### Base image
FROM ghcr.io/github/gh-base-image/go-builder-focal:20241112-230501-gf60b5bcfe@sha256:18511d302f8c16a286669e37ebcd805d7c05ce3084832223bf2576b948d2c4e1 as base

# We passed pkg-mirror-host as a secret to the build but it is not sensitive data.
RUN --mount=type=secret,id=pkg-mirror-host,target=/etc/pkg_mirror_host.txt \
    # This conditional is necessary because the file will not exist in a Codespace.
    if [ -f /etc/pkg_mirror_host.txt ]; then cat /etc/pkg_mirror_host.txt >> /etc/apt/mirrorlist.txt; fi

WORKDIR /app
COPY . .
RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    echo "machine goproxy.githubapp.com login nobody password $(cat .goproxytoken)" > $HOME/.netrc \
    && apt update \
    && go version

### Build the application
FROM base as build
RUN make build

### Runtime image
FROM ghcr.io/github/gh-base-image/gh-fips-base-focal:20241101-171609-g4b647cf2b@sha256:fdb4234872c41f226bc1939e92f15b5dd31bc533508cc47ee45e1f6cdf289690

COPY --chown=github:github --from=build /app/bin/ /app/bin/
WORKDIR /app
EXPOSE 12345

USER github
ENTRYPOINT ["./bin/hydro-processor"]