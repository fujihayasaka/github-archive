# A trivial Dockerfile that lets us test on Linux with this command:
#    $ docker build -f Dockerfile ..
# The context .. is the Go module directory.
FROM ghcr.io/github/gh-base-image/go-builder-noble:20260415-201534-g088085f4b@sha256:2d4aa289dd6ffc83034f48c2650e80598b5a5664ef14df0b78c5325c2710ad20
COPY . .
RUN GOPATH= go test -v ./mysql-lock -dbhost=host.docker.internal
