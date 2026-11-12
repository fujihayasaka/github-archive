# Run with: docker build -f Dockerfile ../..

FROM ghcr.io/github/gh-base-image/go-builder-noble:20260415-201534-g088085f4b@sha256:2d4aa289dd6ffc83034f48c2650e80598b5a5664ef14df0b78c5325c2710ad20 as PageFetch

ENV GOPROXY="https://goproxy.githubapp.com/mod,https://proxy.golang.org/,direct"
ENV GONOSUMDB="github.com/github/*"

COPY go/ /go/src/
COPY script/configure-goproxy /go/src/
WORKDIR /go/src
RUN ./configure-goproxy && \
    go build -o /go/page_fetch ./ecosystem/nuget/page_fetch && \
    go test -c -o /go/page_fetch.test ./ecosystem/nuget/page_fetch

FROM ghcr.io/github/gh-base-image/ruby-builder:v3.2-noble-20260415154956@sha256:fea28dce566bcabf7c3c287dcb52a00f506fb502059796fad7d362baa978a555

WORKDIR /adapter

COPY package_manager_adapters/nuget/Gemfile .
COPY package_manager_adapters/nuget/Gemfile.lock .
COPY package_manager_adapters/nuget/vendor/cache vendor/cache
ENV BUNDLE_FROZEN=true
RUN bundle install --local

COPY package_manager_adapters/nuget/wrapper .
COPY package_manager_adapters/nuget/lib/ ./lib
COPY package_manager_adapters/nuget/test/ ./test
COPY package_manager_adapters/nuget/Rakefile .
COPY --from=PageFetch /go/page_fetch /go/page_fetch.test ./

ENTRYPOINT ["./wrapper"]
