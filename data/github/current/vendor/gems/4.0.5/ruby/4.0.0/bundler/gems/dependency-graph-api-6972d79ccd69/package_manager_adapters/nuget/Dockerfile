# Run with: docker build -f Dockerfile ../..

FROM ghcr.io/github/gh-base-image/go-builder-focal:20260126-232606-g6348120d6@sha256:bc3901cb0fdb9965550fc36d5023eef9a94416d609c703502f65cf547f039fd0 as PageFetch

ENV GOPROXY="https://goproxy.githubapp.com/mod,https://proxy.golang.org/,direct"
ENV GONOSUMDB="github.com/github/*"

COPY go/ /go/src/
COPY script/configure-goproxy /go/src/
WORKDIR /go/src
RUN ./configure-goproxy && \
    go build -o /go/page_fetch ./ecosystem/nuget/page_fetch && \
    go test -c -o /go/page_fetch.test ./ecosystem/nuget/page_fetch

FROM ghcr.io/github/gh-base-image/ruby-builder:v3.2-focal-20260128001043@sha256:37e50d27f362d930c692f3dd67662e8f363140c947458edf163af59d1bc82be2

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
