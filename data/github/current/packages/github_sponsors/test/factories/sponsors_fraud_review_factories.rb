# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsors_fraud_review do
    sponsors_listing { create(:sponsors_listing, :approved, :with_tier, :with_stripe_account) }

    trait :resolved do
      state { 1 }
      reviewer { create(:staff_admin_user) }
      reviewed_at { Time.now }
    end

    trait :flagged do
      state { 2 }
      reviewer { create(:staff_admin_user) }
      reviewed_at { Time.now }
    end
  end

  trait :with_fraud_flagged_sponsor do
    after(:create) do |review|
      create(:fraud_flagged_sponsor, sponsors_fraud_review: review)
    end
  end
end
