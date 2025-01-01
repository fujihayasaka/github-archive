# -*- encoding: utf-8 -*-
# stub: advisory_db_toolkit 1.0.0 ruby lib

Gem::Specification.new do |s|
  s.name = "advisory_db_toolkit".freeze
  s.version = "1.0.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "TODO: Set to your gem server 'https://example.com'", "homepage_uri" => "https://github.com/github/advisory-db/tree/main/packages/advisory_db_toolkit", "rubygems_mfa_required" => "true", "source_code_uri" => "https://github.com/github/advisory-db/tree/main/packages/advisory_db_toolkit" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Advisory Database".freeze]
  s.bindir = "exe".freeze
  s.date = "1980-01-02"
  s.description = "See summary.".freeze
  s.files = ["CHANGELOG.md".freeze, "Gemfile".freeze, "Gemfile.lock".freeze, "LICENSE".freeze, "README.md".freeze, "Rakefile".freeze, "advisory_db_toolkit.gemspec".freeze, "lib/advisory_db_toolkit.rb".freeze, "lib/cve_id_validator.rb".freeze, "lib/ecosystems.rb".freeze, "lib/ecosystems/actions.rb".freeze, "lib/ecosystems/crates.rb".freeze, "lib/ecosystems/ecosystems.rb".freeze, "lib/ecosystems/exceptions.rb".freeze, "lib/ecosystems/go.rb".freeze, "lib/ecosystems/hex.rb".freeze, "lib/ecosystems/maven.rb".freeze, "lib/ecosystems/npm.rb".freeze, "lib/ecosystems/nuget.rb".freeze, "lib/ecosystems/packagist.rb".freeze, "lib/ecosystems/pub.rb".freeze, "lib/ecosystems/pypi.rb".freeze, "lib/ecosystems/ruby_gems.rb".freeze, "lib/ghsa_id_validator.rb".freeze, "lib/osv/README.md".freeze, "lib/osv/interfaces.rb".freeze, "lib/osv/interfaces/advisory.rb".freeze, "lib/osv/interfaces/vulnerability.rb".freeze, "lib/osv/osv.rb".freeze, "lib/osv/transform.rb".freeze, "lib/osv/transformers/schema_v1.rb".freeze, "lib/osv/transformers/schema_v1/affected_package_versions.rb".freeze, "lib/osv/transformers/schema_v1/from_osv_range_parsers/ecosystem.rb".freeze, "lib/osv/transformers/schema_v1/from_osv_range_parsers/exact_version.rb".freeze, "lib/osv/transformers/schema_v1/from_osv_range_parsers/parsed_term.rb".freeze, "lib/osv/transformers/schema_v1/from_osv_range_parsers/parser.rb".freeze, "lib/osv/transformers/schema_v1/from_osv_range_parsers/semver.rb".freeze, "lib/osv/transformers/schema_v1/parsed_range.rb".freeze, "lib/osv/transformers/schema_v1/schema.json".freeze, "lib/osv/transformers/schema_v1/version_spec.rb".freeze, "lib/osv/transformers/schema_v1/vulnerable_version_ranges.rb".freeze, "lib/package_url_obtainer.rb".freeze, "lib/reference_sorter.rb".freeze, "lib/utility.rb".freeze]
  s.homepage = "https://github.com/github/advisory-db/tree/main/packages/advisory_db_toolkit".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.1.0".freeze)
  s.rubygems_version = "3.6.9".freeze
  s.summary = "Gem consolidating common Advisory DB tools, including OSV translation logic for GHSA -> OSV and vice versa.".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<json_schema>.freeze, [">= 0.20.4".freeze, "< 0.22".freeze])
  s.add_runtime_dependency(%q<semantic>.freeze, ["~> 1.6".freeze])
end
