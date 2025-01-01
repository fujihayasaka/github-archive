# frozen_string_literal: true

FactoryBot.define do
  factory :advisory_review_approval do
    user_id { create(:user).id }
    advisory_review_id { nil }
    approved_at { nil }
  end

  trait :approved do
    approved_at { Time.current }
  end
end
