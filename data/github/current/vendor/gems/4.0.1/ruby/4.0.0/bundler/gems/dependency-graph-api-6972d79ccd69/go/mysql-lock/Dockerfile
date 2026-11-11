# A trivial Dockerfile that lets us test on Linux with this command:
#    $ docker build -f Dockerfile ..
# The context .. is the Go module directory.
FROM ghcr.io/github/gh-base-image/go-builder-focal:20260126-232606-g6348120d6@sha256:bc3901cb0fdb9965550fc36d5023eef9a94416d609c703502f65cf547f039fd0
COPY . .
RUN GOPATH= go test -v ./mysql-lock -dbhost=host.docker.internal
