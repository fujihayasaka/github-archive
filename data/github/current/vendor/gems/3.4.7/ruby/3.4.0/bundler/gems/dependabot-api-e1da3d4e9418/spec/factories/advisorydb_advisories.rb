# frozen_string_literal: true

FactoryBot.define do
  factory :advisorydb_advisory, class: "GitHub::Twirp::Advisorydb::Advisory" do
    transient do
      ecosystem { "ECOSYSTEM_RUBYGEMS" }
      name { "rails" }
    end

    ghsa_id { generate(:ghsa_id) }
    cve_id { "CVE-2022-1234" }
    severity { "SEVERITY_HIGH" }
    classification { "CLASSIFICATION_GENERAL" }
    published_at { 1.day.ago }
    updated_at { 1.hour.ago }
    origin { { source: "SOURCE_OPEN_SOURCE" } }
    vulnerable_version_ranges { [build(:vulnerable_version_range, ecosystem: ecosystem, name: name)] }

    initialize_with { new(attributes) }
  end

  factory :vulnerable_version_range, class: "GitHub::Twirp::Advisorydb::VulnerableVersionRange" do
    transient do
      ecosystem { "ECOSYSTEM_RUBYGEMS" }
      name { "rails" }
    end

    package { { ecosystem: ecosystem, name: name } }
    vulnerable_version_range do
      version_ranges = {
        "ECOSYSTEM_RUBYGEMS" => "<= 7.1.0",
        "ECOSYSTEM_NPM" => "<= 1.2.3",
        "ECOSYSTEM_MAVEN" => "<= 14.0.0-M1",
        "ECOSYSTEM_GO" => "<= 0.24.0",
        "ECOSYSTEM_CONDA" => "<= 1.5.0",
        "ECOSYSTEM_PIP" => "<= 1.5.0",
      }
      version_ranges[ecosystem]
    end

    initialize_with { new(attributes) }
  end

  factory :advisories_response, class: "GitHub::Twirp::Advisorydb::AdvisoriesResponse" do
    transient do
      ecosystem { "ECOSYSTEM_RUBYGEMS" }
      name { "rails" }
    end

    advisories { [build(:advisorydb_advisory, ecosystem: ecosystem, name: name)] }

    trait :empty do
      advisories { [] }
    end

    trait :multi_ecosystem do
      advisories do
        [
          build(:advisorydb_advisory, ecosystem: ecosystem, name: name),
          build(:advisorydb_advisory, ecosystem: ecosystem, name: "sinatra"),
          build(:advisorydb_advisory, ecosystem: "ECOSYSTEM_NPM", name: "lodash"),
          build(:advisorydb_advisory, ecosystem: "ECOSYSTEM_MAVEN", name: "org.apache.struts"),
          build(:advisorydb_advisory, ecosystem: "ECOSYSTEM_GO", name: "github.com/golang/protobuf"),
        ]
      end
    end

    initialize_with { new(attributes) }
  end
end
