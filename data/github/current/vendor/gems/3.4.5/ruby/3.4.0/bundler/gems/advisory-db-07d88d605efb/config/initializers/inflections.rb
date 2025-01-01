# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.plural /^(ox)$/i, '\1en'
#   inflect.singular /^(ox)en/i, '\1'
#   inflect.irregular 'person', 'people'
#   inflect.uncountable %w( fish sheep )
# end
#
# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.acronym "API"
  inflect.acronym "CVE"
  inflect.acronym "CVEs"
  inflect.acronym "CVSS"
  inflect.acronym "CWE"
  inflect.acronym "CWEs"
  inflect.acronym "DB"
  inflect.acronym "EPSS"
  inflect.acronym "GHSA"
  inflect.acronym "GHSAs"
  inflect.acronym "GHSL"
  inflect.acronym "GitHub"
  inflect.acronym "ID"
  inflect.acronym "IDs"
  inflect.acronym "JSON"
  inflect.acronym "MITRE"
  inflect.acronym "NPM"
  inflect.acronym "NVD"
  inflect.acronym "OSV"
  inflect.acronym "PHP"
  inflect.acronym "PR"
  inflect.acronym "PRs"
  inflect.acronym "UTF8"
  inflect.acronym "VEA"
  inflect.acronym "YAML"
end
