FROM ghcr.io/github/gh-base-image/gh-builder-focal:20241125-231619-gb34417c28@sha256:1aa816d4347ae74f5cdbb640ef3a4eb512943223651fa2044cd820c7b6d31be5 AS base

WORKDIR /root/go/src/github.com/github/blackbird-mw

COPY . .

RUN go build ./internal/test/cmd/fakegithub/main.go

EXPOSE 11223

CMD ["go", "run", "./internal/test/cmd/fakegithub/main.go"]
