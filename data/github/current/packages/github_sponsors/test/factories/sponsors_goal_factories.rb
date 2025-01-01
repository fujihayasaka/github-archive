# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsors_goal do
    transient do
      tier_count { 1 }
    end
    listing { create(:sponsors_listing, :approved, :with_stripe_account, tier_count: tier_count) }
    description { Faker::Lorem.sentence }
    target_value { 1 }

    trait :monthly_sponsorship_amount do
      kind { :monthly_sponsorship_amount }
    end

    trait :total_sponsors_count do
      kind { :total_sponsors_count }
    end

    trait :active do
      state { :active }
    end

    trait :completed do
      state { :completed }
      completed_at { Time.current }
    end

    trait :retired do
      state { :retired }
      retired_at { Time.current }
    end
  end
end
