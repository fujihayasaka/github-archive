# Run with: docker build -f Dockerfile ../..

FROM ghcr.io/github/gh-base-image/go-builder-focal:20250725-230825-g446ca4a55@sha256:d96b80c9a7e65082721e590525488e2e60a3c18066edc2f9f31df07c2d4bed21 as PageFetch

ENV GOPROXY="https://goproxy.githubapp.com/mod,https://proxy.golang.org/,direct"
ENV GONOSUMDB="github.com/github/*"

COPY go/ /go/src/
COPY script/configure-goproxy /go/src/
WORKDIR /go/src
RUN ./configure-goproxy && \
    go build -o /go/page_fetch ./ecosystem/nuget/page_fetch && \
    go test -c -o /go/page_fetch.test ./ecosystem/nuget/page_fetch

FROM ghcr.io/github/gh-base-image/ruby-builder:v3.2-focal-20250725231330@sha256:53eb5ccacd82ad45ab8333b6538af233c6ebd7b726bf6e3ad4399a38c23551d8

WORKDIR /adapter

COPY package_manager_adapters/nuget/Gemfile .
COPY package_manager_adapters/nuget/Gemfile.lock .
COPY package_manager_adapters/nuget/wrapper .
COPY package_manager_adapters/nuget/lib/ ./lib
COPY package_manager_adapters/nuget/test/ ./test
COPY package_manager_adapters/nuget/Rakefile .
COPY --from=PageFetch /go/page_fetch /go/page_fetch.test ./

RUN bundle install

ENTRYPOINT ["./wrapper"]
