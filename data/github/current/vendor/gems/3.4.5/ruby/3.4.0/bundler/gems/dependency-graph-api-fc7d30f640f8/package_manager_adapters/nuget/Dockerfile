# Run with: docker build -f Dockerfile ../..

FROM ghcr.io/github/gh-base-image/go-builder-focal:20250304-230608-gdb548f850@sha256:03ec13b4aa1d36ad9f1b847944bcdb61e3df781f326c2c71629ac8328ac84891 as PageFetch

ENV GOPROXY="https://goproxy.githubapp.com/mod,https://proxy.golang.org/,direct"
ENV GONOSUMDB="github.com/github/*"

COPY go/ /go/src/
COPY script/configure-goproxy /go/src/
WORKDIR /go/src
RUN ./configure-goproxy && \
    go build -o /go/page_fetch ./ecosystem/nuget/page_fetch && \
    go test -c -o /go/page_fetch.test ./ecosystem/nuget/page_fetch

FROM ghcr.io/github/gh-base-image/ruby-builder:v3.2-focal-20250305010021@sha256:1ee09008b967fcc62c2351c54d4ba8df0a59d3a4fe11cc47c5b23feb96c1318b

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
