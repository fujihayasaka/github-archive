# ===================================================================
# Main Docker image for production builds
# ===================================================================
FROM ghcr.io/github/gh-base-image/gh-builder-focal:latest AS build

WORKDIR /go/src/github.com/github/notifyd
ADD . .
RUN make prod

FROM ghcr.io/github/gh-base-image/gh-base-focal:20250303-142242-g3659d9547 AS run

# Temporary because the base image doesn't have curl

# We passed pkg-mirror-host as a secret to the build but it is not sensitive data.
RUN --mount=type=secret,id=pkg-mirror-host,target=/etc/pkg_mirror_host.txt \
    if [ -f /etc/pkg_mirror_host.txt ]; then cat /etc/pkg_mirror_host.txt >> /etc/apt/mirrorlist.txt; fi

RUN --mount=type=secret,id=apt-auth-conf,target=/etc/apt/auth.conf.d/apt_auth.conf \
    apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

COPY --from=build /go/src/github.com/github/notifyd/bin/api /go/bin/api
COPY --from=build /go/src/github.com/github/notifyd/bin/delete-repository /go/bin/delete-repository
COPY --from=build /go/src/github.com/github/notifyd/bin/delete-repository-for-users /go/bin/delete-repository-for-users
COPY --from=build /go/src/github.com/github/notifyd/bin/delete-user /go/bin/delete-user
COPY --from=build /go/src/github.com/github/notifyd/bin/delete-user-repositories /go/bin/delete-user-repositories
COPY --from=build /go/src/github.com/github/notifyd/bin/email /go/bin/email
COPY --from=build /go/src/github.com/github/notifyd/bin/mobile /go/bin/mobile
COPY --from=build /go/src/github.com/github/notifyd/bin/notify /go/bin/notify
COPY --from=build /go/src/github.com/github/notifyd/bin/transition-job /go/bin/transition-job

RUN groupadd -g 700 notifyd && \
    useradd -r -u 700 -g notifyd notifyd
USER notifyd

# chatops
EXPOSE 8082

# twirp API
EXPOSE 8080

CMD ["/go/bin/api"]
