# frozen_string_literal: true

FactoryBot.define do
  factory :cve do
    sequence(:cve_id, 1234) { |n| "CVE-2022-#{n}" }
    year { cve_id ? cve_id.split("-")[1].to_i : nil }
  end
end
