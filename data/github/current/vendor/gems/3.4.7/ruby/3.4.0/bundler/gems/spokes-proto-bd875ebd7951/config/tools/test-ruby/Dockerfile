FROM ruby:3.1.2

WORKDIR /work/src

ADD gen/ruby/Gemfile                            Gemfile
ADD gen/ruby/spokes-proto.gemspec               spokes-proto.gemspec
ADD gen/ruby/lib/github/spokes/proto/version.rb lib/github/spokes/proto/version.rb
RUN bundle install

ADD gen/ruby .

ADD config/tools/test-ruby/test /work/test

ENTRYPOINT ["/work/test"]
