# The official "buf" image doesn't contain Go, and installing buf on a Golang image takes too long.
# So, we use the official "buf" image to copy the binaries to the Go image
FROM bufbuild/buf:1.28.1 AS buf_image

FROM golang:1.23
ARG protoc_gen_go_version=v1.5.3
ARG protoc_gen_twirp_version=v8.0.0
ARG protoc_gen_validate_version=v1.0.3
ARG protoc_gen_twirp_ruby_version=v1.9.0
ARG USER_UID=1000
ARG USER_GID=1000

COPY --from=buf_image /usr/local/bin/buf /usr/local/bin/buf

# Install the protoc-gen-go and protoc-gen-twirp plugins in order to generate go and twirp code.
RUN go install github.com/golang/protobuf/protoc-gen-go@${protoc_gen_go_version}
RUN go install github.com/twitchtv/twirp/protoc-gen-twirp@${protoc_gen_twirp_version}
RUN go install github.com/envoyproxy/protoc-gen-validate@${protoc_gen_validate_version}
RUN go install github.com/twitchtv/twirp-ruby/protoc-gen-twirp_ruby@${protoc_gen_twirp_ruby_version}

# Create a user with ID 1000 to make sure that generated files are created on mounted volume with correct permissions.
RUN groupadd -g $USER_GID buf || true
RUN useradd -rm -d /home/buf -s /bin/bash -g $USER_GID -u $USER_UID buf
USER buf

ENTRYPOINT ["/usr/local/bin/buf"]