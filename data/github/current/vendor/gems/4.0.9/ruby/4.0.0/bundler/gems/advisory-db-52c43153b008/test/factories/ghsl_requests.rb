# frozen_string_literal: true

FactoryBot.define do
  factory :ghsl_request do
    cve_review
    sequence(:ghsl_id) { |n| "GHSL-#{Time.zone.now.year}-#{n.to_s.rjust(3, "0")}" }
    ghsl_issue { "https://securitylab.github.com/advisories/#{ghsl_id}_some_thing/" }
  end
end
