ARG RUBY_VERSION=3.0.3
FROM ruby:${RUBY_VERSION}-buster
WORKDIR /srv/gem
COPY lib/service-catalog/client/version.rb lib/service-catalog/client/version.rb
COPY Gemfile service-catalog-client.gemspec ./
RUN set -ex \
  && gem install bundler -v 2.1.4  \
  && bundle install --jobs=4
COPY . .

CMD [ "bundle", "exec", "rake", "test" ]
