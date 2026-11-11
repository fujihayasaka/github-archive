# -*- encoding: utf-8 -*-
# stub: rqrcode 3.1.0 ruby lib

Gem::Specification.new do |s|
  s.name = "rqrcode".freeze
  s.version = "3.1.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/whomwah/rqrcode/issues", "changelog_uri" => "https://github.com/whomwah/rqrcode/blob/main/CHANGELOG.md" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Duncan Robertson".freeze]
  s.bindir = "exe".freeze
  s.date = "1980-01-02"
  s.description = "rqrcode is a library for encoding QR Codes. The simple\ninterface allows you to create QR Code data structures\nand then render them in the way you choose.\n".freeze
  s.email = ["duncan@whomwah.com".freeze]
  s.files = [".github/FUNDING.yml".freeze, ".github/workflows/ruby.yml".freeze, ".gitignore".freeze, ".rspec".freeze, ".standard.yml".freeze, "CHANGELOG.md".freeze, "Gemfile".freeze, "Gemfile.lock".freeze, "LICENSE.txt".freeze, "README.md".freeze, "Rakefile".freeze, "_config.yml".freeze, "bin/console".freeze, "images/ansi-screen-shot.png".freeze, "images/github-qrcode.png".freeze, "images/github-qrcode.svg".freeze, "lib/rqrcode.rb".freeze, "lib/rqrcode/export.rb".freeze, "lib/rqrcode/export/ansi.rb".freeze, "lib/rqrcode/export/html.rb".freeze, "lib/rqrcode/export/png.rb".freeze, "lib/rqrcode/export/svg.rb".freeze, "lib/rqrcode/qrcode.rb".freeze, "lib/rqrcode/qrcode/qrcode.rb".freeze, "lib/rqrcode/version.rb".freeze, "rqrcode.gemspec".freeze]
  s.homepage = "https://github.com/whomwah/rqrcode".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.0".freeze)
  s.rubygems_version = "3.6.9".freeze
  s.summary = "A library to encode QR Codes".freeze

  s.installed_by_version = "4.0.10".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<rqrcode_core>.freeze, ["~> 2.0".freeze])
  s.add_runtime_dependency(%q<chunky_png>.freeze, ["~> 1.0".freeze])
  s.add_development_dependency(%q<bundler>.freeze, ["~> 2.0".freeze])
  s.add_development_dependency(%q<rake>.freeze, ["~> 13.0".freeze])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 3.5".freeze])
  s.add_development_dependency(%q<standard>.freeze, ["~> 1.41".freeze])
end
