# -*- encoding: utf-8 -*-
# stub: sweagentd 0.1.0 ruby lib

Gem::Specification.new do |s|
  s.name = "sweagentd".freeze
  s.version = "0.1.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["GitHub".freeze]
  s.date = "1980-01-02"
  s.files = ["lib/proto/jobs/v1/jobs_api_pb.rb".freeze, "lib/proto/jobs/v1/jobs_api_twirp.rb".freeze, "lib/sweagentd.rb".freeze]
  s.homepage = "https://github.com/github/sweagentd".freeze
  s.licenses = ["Nonstandard".freeze]
  s.rubygems_version = "4.0.3".freeze
  s.summary = "Generated client for sweagentd.".freeze

  s.installed_by_version = "4.0.20".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<rack>.freeze, [">= 2.2.3".freeze])
  s.add_runtime_dependency(%q<twirp>.freeze, ["<= 1.12.0".freeze])
  s.add_development_dependency(%q<bundler>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
end
