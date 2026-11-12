# frozen_string_literal: true

FactoryBot.define do
  factory :advisory_improvement_data, class: AdvisoryImprovementData do
    skip_create
    ghsa_id
    summary { "This is a test advisory title" }
    description { "This is a test advisory description" }
    source_code_location { "" }
    severity { "low" }
    cvss_v3 { "" }
    cvss_v4 { "" }
    cwe_ids { [] }
    references { [] }
    affected_products { [] }
    actor_id { 1234 }
    actor_login { "testuser" }
  end
end
