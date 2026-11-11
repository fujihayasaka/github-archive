FROM --platform=linux/amd64 golang:1.26.1@sha256:c42e4d75186af6a44eb4159dcfac758ef1c05a7011a0052fe8a8df016d8e8fb9

# Protoc binary:
RUN apt-get -qq update && \
  apt-get -y --no-install-recommends install \
    unzip && \
  rm -rf /var/lib/apt/lists/*
# Updating this version is blocked, https://github.com/github/dependabot-updates/issues/10793
ARG PROTOC_VERSION=22.4
ARG PROTOC_SHASUM=b3cff4d4076efe2965e8560cae6307c429349eda0af7755950d6ea5db6d72870
RUN curl -o /tmp/protoc.zip -L https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-x86_64.zip \
  && (echo "${PROTOC_SHASUM} /tmp/protoc.zip" | sha256sum -c) \
  && unzip -d /usr/local /tmp/protoc.zip \
  && rm /tmp/protoc.zip

COPY proto/dependabot-api/go.mod proto/dependabot-api/go.sum /app/
WORKDIR /app
RUN go mod download

RUN go install github.com/arthurnn/twirp-ruby/protoc-gen-twirp_ruby@v1.14.1
COPY script/protoc /protoc.sh
ENV IN_CONTAINER=1
ENTRYPOINT ["/protoc.sh"]
