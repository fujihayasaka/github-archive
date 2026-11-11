# frozen_string_literal: true

FactoryBot.define do
  CHAR_MAP = { # rubocop:disable Lint/ConstantDefinitionInBlock
    "0" => "2",
    "1" => "3",
    "2" => "4",
    "3" => "5",
    "4" => "6",
    "5" => "7",
    "6" => "8",
    "7" => "9",
    "8" => "c",
    "9" => "f",
  }.freeze

  sequence :ghsa_id do |n|
    id = n.to_s.chars.map { |c| CHAR_MAP.fetch(c) }.join
    padded_id = id.rjust(12, "x").gsub(/(.{4})/, '-\1').gsub(/^-/, "")
    "GHSA-#{padded_id}"
  end

  sequence :ghis_id do |n|
    id = n.to_s.chars.map { |c| CHAR_MAP.fetch(c) }.join
    padded_id = id.rjust(12, "x").gsub(/(.{4})/, '-\1').gsub(/^-/, "")
    "GHIS-#{padded_id}"
  end

  factory :github_security_advisory do
    ghsa_id { generate(:ghsa_id) }
    dependency_name { "business" }
    package_manager { "bundler" }
    affected_versions { ["<= 1.10.0"] }
    patched_versions { ["~> 1.11.0"] }
    github_updated_at { 1.hour.ago }

    trait :withdrawn do
      withdrawn_at { 15.minutes.ago }
    end

    trait :innersource do
      ghsa_id { generate(:ghis_id) }
    end

    initialize_with { new(attributes) }
  end
end
