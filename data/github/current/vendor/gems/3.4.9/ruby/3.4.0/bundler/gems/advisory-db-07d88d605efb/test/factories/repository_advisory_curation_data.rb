# frozen_string_literal: true

FactoryBot.define do
  factory :repository_advisory_curation_data, class: RepositoryAdvisoryCurationData do
    skip_create
    ghsa_id
    title { "This is a test advisory title" }
    description { "This is a test advisory description" }
    cve_id { "" }
    permalink { "https://github.com/testorg/testrepo/security/advisories/#{ghsa_id}" }
    severity { "low" }
    cvss_v3 { "" }
    cvss_v4 { "" }
    cwe_ids { [] }
    affected_products do
      [{ "package_ecosystem" => "cargo",
         "package_name" => "popular_package",
         "vulnerable_version_range" => "< 1.2.3",
         "first_patched_version" => "1.2.3" }]
    end
  end
end
