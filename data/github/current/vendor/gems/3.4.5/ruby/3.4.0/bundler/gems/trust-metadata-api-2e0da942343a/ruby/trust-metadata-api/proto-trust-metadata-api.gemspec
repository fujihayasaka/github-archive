# -*- encoding: utf-8 -*-
# stub: proto-trust-metadata-api 0.18.0 ruby lib

Gem::Specification.new do |s|
  s.name = "proto-trust-metadata-api".freeze
  s.version = "0.18.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/github/trust-metadata-api", "source_code_uri" => "https://github.com/github/trust-metadata-api" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Package Security".freeze]
  s.date = "1980-01-02"
  s.description = "Trust Metadata API Ruby client".freeze
  s.email = ["package-security@github.com".freeze]
  s.files = ["CHANGELOG.md".freeze, "Gemfile".freeze, "Gemfile.lock".freeze, "README.md".freeze, "Rakefile".freeze, "lib/proto-trust-metadata-api.rb".freeze, "lib/proto/trust-metadata-api/request_hmac.rb".freeze, "lib/proto/trust-metadata-api/v0/service_pb.rb".freeze, "lib/proto/trust-metadata-api/v0/service_twirp.rb".freeze, "lib/proto/trust-metadata-api/version.rb".freeze, "proto-trust-metadata-api.gemspec".freeze, "sorbet/config".freeze, "sorbet/rbi/annotations/.gitattributes".freeze, "sorbet/rbi/annotations/faraday.rbi".freeze, "sorbet/rbi/annotations/minitest.rbi".freeze, "sorbet/rbi/annotations/webmock.rbi".freeze, "sorbet/rbi/dsl/.gitattributes".freeze, "sorbet/rbi/gems/.gitattributes".freeze, "sorbet/rbi/gems/addressable@2.8.7.rbi".freeze, "sorbet/rbi/gems/base64@0.2.0.rbi".freeze, "sorbet/rbi/gems/benchmark@0.4.0.rbi".freeze, "sorbet/rbi/gems/bigdecimal@3.1.9.rbi".freeze, "sorbet/rbi/gems/coderay@1.1.3.rbi".freeze, "sorbet/rbi/gems/crack@1.0.0.rbi".freeze, "sorbet/rbi/gems/erubi@1.13.1.rbi".freeze, "sorbet/rbi/gems/faraday-net_http@3.4.0.rbi".freeze, "sorbet/rbi/gems/faraday@2.12.2.rbi".freeze, "sorbet/rbi/gems/google-protobuf@3.25.6.rbi".freeze, "sorbet/rbi/gems/googleapis-common-protos-types@1.7.0.rbi".freeze, "sorbet/rbi/gems/hashdiff@1.1.2.rbi".freeze, "sorbet/rbi/gems/json@2.10.2.rbi".freeze, "sorbet/rbi/gems/logger@1.6.6.rbi".freeze, "sorbet/rbi/gems/method_source@1.1.0.rbi".freeze, "sorbet/rbi/gems/minitest@5.25.4.rbi".freeze, "sorbet/rbi/gems/net-http@0.6.0.rbi".freeze, "sorbet/rbi/gems/netrc@0.11.0.rbi".freeze, "sorbet/rbi/gems/parallel@1.26.3.rbi".freeze, "sorbet/rbi/gems/prism@1.3.0.rbi".freeze, "sorbet/rbi/gems/pry@0.15.2.rbi".freeze, "sorbet/rbi/gems/public_suffix@6.0.1.rbi".freeze, "sorbet/rbi/gems/rack@3.1.12.rbi".freeze, "sorbet/rbi/gems/rake@13.2.1.rbi".freeze, "sorbet/rbi/gems/rbi@0.2.4.rbi".freeze, "sorbet/rbi/gems/rexml@3.4.1.rbi".freeze, "sorbet/rbi/gems/sigstore-proto@0.1.0.rbi".freeze, "sorbet/rbi/gems/spoom@1.5.4.rbi".freeze, "sorbet/rbi/gems/tapioca@0.16.11.rbi".freeze, "sorbet/rbi/gems/thor@1.3.2.rbi".freeze, "sorbet/rbi/gems/twirp@1.10.0.rbi".freeze, "sorbet/rbi/gems/uri@1.0.3.rbi".freeze, "sorbet/rbi/gems/vcr@6.3.1.rbi".freeze, "sorbet/rbi/gems/webmock@3.25.0.rbi".freeze, "sorbet/rbi/gems/yard-sorbet@0.9.0.rbi".freeze, "sorbet/rbi/gems/yard@0.9.37.rbi".freeze, "sorbet/tapioca/config.yml".freeze, "sorbet/tapioca/require.rb".freeze]
  s.homepage = "https://github.com/github/trust-metadata-api".freeze
  s.required_ruby_version = Gem::Requirement.new(">= 3.3".freeze)
  s.rubygems_version = "3.6.7".freeze
  s.summary = "Trust Metadata API Ruby client".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.1".freeze])
  s.add_runtime_dependency(%q<faraday>.freeze, [">= 0.17".freeze])
  s.add_runtime_dependency(%q<sorbet-runtime>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<sigstore-proto>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<bundler>.freeze, ["~> 2.5".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.25".freeze])
  s.add_development_dependency(%q<pry>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rack>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<vcr>.freeze, ["~> 6.3".freeze])
  s.add_development_dependency(%q<webmock>.freeze, ["~> 3.23".freeze])
  s.add_development_dependency(%q<sorbet>.freeze, [">= 0".freeze])
end
