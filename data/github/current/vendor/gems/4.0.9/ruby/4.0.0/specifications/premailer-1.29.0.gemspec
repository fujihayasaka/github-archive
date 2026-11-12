# -*- encoding: utf-8 -*-
# stub: premailer 1.29.0 ruby lib

Gem::Specification.new do |s|
  s.name = "premailer".freeze
  s.version = "1.29.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "rubygems_mfa_required" => "true", "yard.run" => "yri" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Alex Dunae".freeze]
  s.date = "1980-01-02"
  s.description = "Improve the rendering of HTML emails by making CSS inline, converting links and warning about unsupported code.".freeze
  s.email = "akzhan.abdulin@gmail.com".freeze
  s.executables = ["premailer".freeze]
  s.files = ["bin/premailer".freeze]
  s.homepage = "https://github.com/premailer/premailer".freeze
  s.licenses = ["BSD-3-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.3".freeze)
  s.rubygems_version = "3.6.9".freeze
  s.summary = "Preflight for HTML e-mail.".freeze

  s.installed_by_version = "4.0.20".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<addressable>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<css_parser>.freeze, [">= 1.19.0".freeze])
  s.add_runtime_dependency(%q<htmlentities>.freeze, [">= 4.0.0".freeze])
end
