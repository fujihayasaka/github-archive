# frozen_string_literal: true

FactoryBot.define do
  factory :campaign do
    name { SecureRandom.hex(10) }
    advisory_reviews { create_list(:advisory_review, review_count, :curation_state_open) }

    transient do
      review_count { 5 }
    end

    trait :complete do
      after(:create) do |campaign|
        campaign.advisory_reviews.each do |advisory_review|
          advisory_review.record_curation_decision(type: "advisory_review", decision: "close", curator: "monalisa")
        end
      end
    end
  end
end
