# frozen_string_literal: true

FactoryBot.define do
  factory :mitre_cve_submission do
    cve_review
    pull_request_url { "api" }
  end
end
