# A trivial Dockerfile that lets us test on Linux with this command:
#    $ docker build -f Dockerfile ..
# The context .. is the Go module directory.
FROM ghcr.io/github/gh-base-image/go-builder-focal:20251017-145146-g68227e4f2@sha256:952c4ad8f1f1622c98afe1c894b8b7493590ca256190cf11ddf4abbdf92f87eb
COPY . .
RUN GOPATH= go test -v ./mysql-lock -dbhost=host.docker.internal
