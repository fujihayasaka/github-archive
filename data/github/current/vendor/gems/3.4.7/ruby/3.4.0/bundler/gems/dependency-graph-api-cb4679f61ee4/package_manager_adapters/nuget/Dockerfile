# Run with: docker build -f Dockerfile ../..

FROM ghcr.io/github/gh-base-image/go-builder-focal:20251017-145146-g68227e4f2@sha256:952c4ad8f1f1622c98afe1c894b8b7493590ca256190cf11ddf4abbdf92f87eb as PageFetch

ENV GOPROXY="https://goproxy.githubapp.com/mod,https://proxy.golang.org/,direct"
ENV GONOSUMDB="github.com/github/*"

COPY go/ /go/src/
COPY script/configure-goproxy /go/src/
WORKDIR /go/src
RUN ./configure-goproxy && \
    go build -o /go/page_fetch ./ecosystem/nuget/page_fetch && \
    go test -c -o /go/page_fetch.test ./ecosystem/nuget/page_fetch

FROM ghcr.io/github/gh-base-image/ruby-builder:v3.2-focal-20251017152956@sha256:6d661ef82f68444383f30d8dc96d308562cfe1c11800b781031f7ddbab4440bc

WORKDIR /adapter

COPY package_manager_adapters/nuget/Gemfile .
COPY package_manager_adapters/nuget/Gemfile.lock .
COPY package_manager_adapters/nuget/vendor/cache vendor/cache
RUN bundle install --local

COPY package_manager_adapters/nuget/wrapper .
COPY package_manager_adapters/nuget/lib/ ./lib
COPY package_manager_adapters/nuget/test/ ./test
COPY package_manager_adapters/nuget/Rakefile .
COPY --from=PageFetch /go/page_fetch /go/page_fetch.test ./

ENTRYPOINT ["./wrapper"]
