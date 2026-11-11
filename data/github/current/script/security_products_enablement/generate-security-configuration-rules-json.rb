#!/usr/bin/env ruby
# typed: true
# frozen_string_literal: true

# Generates the security-configuration-rules.json file in the github-ui repo
# from the Ruby FeatureRegistry.
#
# Usage:
#   bin/rails runner script/security_products_enablement/generate-security-configuration-rules-json.rb
#
# Requires github-ui to be checked out at /workspaces/github-ui.

dest = "/workspaces/github-ui/packages/security-products-enablement/data/security-configuration-rules.json"

unless Dir.exist?("/workspaces/github-ui")
  abort "ERROR: github-ui is not checked out at /workspaces/github-ui"
end

rules = SecurityProductsEnablement::SecurityConfigurationRules::FeatureRegistry.as_json
rules_json = JSON.pretty_generate(rules) + "\n"
sha = Digest::SHA256.hexdigest(rules_json)

json = JSON.pretty_generate(
  {
    "_comment" => "AUTO-GENERATED from github/github FeatureRegistry — do not edit manually. Regenerate with: bin/rails runner script/security_products_enablement/generate-security-configuration-rules-json.rb",
    "_sha256" => sha,
  }.merge(rules),
)
File.write(dest, json + "\n")

puts "Wrote #{dest}"
