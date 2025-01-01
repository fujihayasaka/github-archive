# A trivial Dockerfile that lets us test on Linux with this command:
#    $ docker build -f Dockerfile ..
# The context .. is the Go module directory.
FROM ghcr.io/github/gh-base-image/go-builder-focal:20250725-230825-g446ca4a55@sha256:d96b80c9a7e65082721e590525488e2e60a3c18066edc2f9f31df07c2d4bed21
COPY . .
RUN GOPATH= go test -v ./mysql-lock -dbhost=host.docker.internal
