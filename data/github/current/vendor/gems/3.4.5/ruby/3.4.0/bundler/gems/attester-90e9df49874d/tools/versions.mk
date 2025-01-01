# This file contains version pins for all of dependencies loaded in our protoc
# builder image:
#   - The protoc CLI
#   - protoc plugins for Go, Ruby, and Twirp
#   - 3rd-party protobufs referenced by our service

# release tag from https://github.com/protocolbuffers/protobuf
# keep synced with:
# https://github.com/github/monolith-twirp-tools/blob/main/.github/workflows/workflow-build-image.yaml#L16
PROTOC_VERSION=v3.15.4

# sha256 of protoc zip file
#   sha256sum protoc-${PROTOC_VERSION#v}-linux-x86_64.zip | awk '{print "sha256:" $1 }'
PROTOC_CHECKSUM=sha256:14cca6414353c965ecf3c6bfc5aefb5b54cbd2f572b61aa67bf1ca435b086db9

# release tag from https://github.com/twitchtv/twirp/
PROTOC_TWIRP_VERSION=v8.1.3

# release tag from https://github.com/golang/protobuf
PROTOC_GO_VERSION=v1.5.2

# release tag from https://github.com/github/twirp-ruby
# keep synced with:
# https://github.com/github/monolith-twirp-tools/blob/main/gen/ruby/Dockerfile#L12
PROTOC_TWIRP_RUBY_VERSION=v1.10.0

# git commit from https://github.com/googleapis/googleapis
GOOGLEAPIS_COMMIT=2f37e0ad56637325b24f8603284ccb6f05796f9a

# git commit from https://github.com/sigstore/protobuf-specs
SIGSTORE_COMMIT=68cc7d273f0a2ade2f8c9c56c0da094f481eabd5

# git commit from https://github.com/in-toto/attestation
INTOTO_COMMIT=5cebcc85e8820786cedcb8a535190d673001deb6
