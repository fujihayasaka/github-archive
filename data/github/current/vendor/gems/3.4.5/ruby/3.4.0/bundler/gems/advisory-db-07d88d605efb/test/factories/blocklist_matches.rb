# frozen_string_literal: true

FactoryBot.define do
  factory :blocklist_match do
    blocklisted_term
    advisory_review
  end
end
