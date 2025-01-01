# typed: strict
# frozen_string_literal: true

ActiveSupport::Inflector.inflections do |inflect|
  inflect.acronym "CVE"
  inflect.acronym "CWE"
  inflect.acronym "DGit"
  inflect.acronym "EPSS"
  inflect.acronym "GitHub"
  inflect.acronym "ISO3166"
  inflect.acronym "NumFOCUS"
  inflect.acronym "OFAC"
  inflect.acronym "OIDC"
  inflect.acronym "OSV"
  inflect.acronym "RBI"
  inflect.acronym "SpokesAPI"
  inflect.acronym "SCIM"
  inflect.acronym "SKU"
  inflect.acronym "UI"
  inflect.acronym "UUID"
  inflect.acronym "SBOM"

  inflect.irregular "has", "have"
  inflect.irregular "is", "are"
  inflect.irregular "was", "were"
  inflect.irregular "analysis", "analyses"
  inflect.irregular "this", "these"
end
