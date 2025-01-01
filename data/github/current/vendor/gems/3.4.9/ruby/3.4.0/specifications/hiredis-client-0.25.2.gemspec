# -*- encoding: utf-8 -*-
# stub: hiredis-client 0.25.2 ruby lib
# stub: ext/redis_client/hiredis/extconf.rb

Gem::Specification.new do |s|
  s.name = "hiredis-client".freeze
  s.version = "0.25.2".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "https://rubygems.org", "changelog_uri" => "https://github.com/redis-rb/redis-client/blob/master/CHANGELOG.md", "homepage_uri" => "https://github.com/redis-rb/redis-client", "source_code_uri" => "https://github.com/redis-rb/redis-client" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Jean Boussier".freeze]
  s.date = "2025-08-10"
  s.email = ["jean.boussier@gmail.com".freeze]
  s.extensions = ["ext/redis_client/hiredis/extconf.rb".freeze]
  s.files = ["ext/redis_client/hiredis/extconf.rb".freeze]
  s.homepage = "https://github.com/redis-rb/redis-client".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.6.0".freeze)
  s.rubygems_version = "3.6.2".freeze
  s.summary = "Hiredis binding for redis-client".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<redis-client>.freeze, ["= 0.25.2".freeze])
end
