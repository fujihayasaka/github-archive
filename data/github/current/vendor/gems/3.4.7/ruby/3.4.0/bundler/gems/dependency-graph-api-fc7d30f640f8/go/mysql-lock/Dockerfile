# A trivial Dockerfile that lets us test on Linux with this command:
#    $ docker build -f Dockerfile ..
# The context .. is the Go module directory.
FROM ghcr.io/github/gh-base-image/go-builder-focal:20250304-230608-gdb548f850@sha256:03ec13b4aa1d36ad9f1b847944bcdb61e3df781f326c2c71629ac8328ac84891
COPY . .
RUN GOPATH= go test -v ./mysql-lock -dbhost=host.docker.internal
