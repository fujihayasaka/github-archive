FROM ghcr.io/github/gh-base-image/gh-builder-focal:latest AS build

ENV GOPATH=/go/
ENV GOBIN=/go/bin/

ADD . /go/src/github.com/github/authnd
WORKDIR /go/src/github.com/github/authnd

# CGO_ENABLED=0 will statically link the go program so we can use scratch
RUN CGO_ENABLED=0 go install ./cmd/authnd

# generate token exchange signing key
RUN OUT="/tmp/ta-signing-key" script/gen-ecdsa-p256-keypair
# generate keys required for the identity service
RUN mkdir -p /tmp/identity-keys
RUN OUT="/tmp/identity-keys" script/gen-rsa256-private-key

FROM ruby:3.4.1

WORKDIR /usr/src/app

COPY --from=build /go/bin/authnd /usr/bin/authnd
COPY --from=build /tmp/ta-signing-key.* /usr/src/app/dev/
COPY --from=build /tmp/identity-keys /usr/src/app/dev/

ENV AUTHND_BIN_PATH=/usr/bin/authnd

ADD Gemfile Gemfile
ADD Gemfile.lock Gemfile.lock
ADD authnd-client.gemspec authnd-client.gemspec
ADD ruby/lib/authnd-client/version.rb ruby/lib/authnd-client/version.rb

RUN bundle install --with="test development"

ADD . .

RUN bundle exec ruby -e "require 'authnd-client'" -e "puts 'ok'"
RUN make ruby-client-ci
RUN gem build authnd-client.gemspec
