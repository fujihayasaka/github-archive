# frozen_string_literal: true

require "normal_yaml"

FactoryBot.define do
  factory :cve_request do
    ghsa_id
    actor_id { 1234 }
    actor_login { "gimmecve" }
    advisory_permalink { "https://github.com/testorg/testrepo/security/advisories/#{ghsa_id}" }
    advisory_state { "draft" }
    title { "test repository advisory title" }
    description { build(:description) }
    affected_products_payload { build_list(:affected_products_payload_item, 1) }
  end

  factory :affected_products_payload_item, class: Hash do
    skip_create
    initialize_with { NormalYAML.normalize(attributes) }

    ecosystem { "npm" }
    package { "vulnerable_package" }
    affected_versions { "< 1.2.3" }
    patches { "1.2.3" }
  end

  trait :with_cvss_v3 do
    cvss_v3 { "CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:H/I:N/A:N" }
  end

  trait :with_cvss_v4 do
    cvss_v4 { "CVSS:4.0/AV:A/AC:H/AT:N/PR:L/UI:N/VC:L/VI:H/VA:H/SC:H/SI:L/SA:H" }
  end
end
