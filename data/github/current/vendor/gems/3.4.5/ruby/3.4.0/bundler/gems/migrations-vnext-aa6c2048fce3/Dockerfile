FROM ghcr.io/github/gh-base-image/go-builder-focal:20250115-230609-gf14caf31c@sha256:c9e84fcba12dd87a1768a2f34aaa1160b26469a6f41b3873092e68c9b108c734 AS gobuilder
WORKDIR /go

COPY script/configure-goproxy ./

# Build modabins
ADD . /go
RUN ./configure-goproxy
RUN make modabins

# Copy modabins
FROM ghcr.io/github/gh-base-image/gh-base-focal:20250210-144822-g9ed4ec84d

USER github
COPY --from=gobuilder --chown=github:github /go/modabin/mvnworker ./
COPY --from=gobuilder --chown=github:github /go/modabin/mvndlworker ./
COPY --from=gobuilder --chown=github:github /go/modabin/event-worker ./
COPY --from=gobuilder --chown=github:github /go/modabin/eventdlworker ./
COPY --from=gobuilder --chown=github:github /go/modabin/mvndagworker ./