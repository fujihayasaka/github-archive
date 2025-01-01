# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsors_patreon_user do
    transient do
      patreon_tier_count { 0 }
    end

    association :user, factory: [:user, :sponsorable]
    patreon_user_id { SecureRandom.hex(12) }
    patreon_email { Faker::Internet.email }
    patreon_username { user.display_login }
    patreon_access_token { SecureRandom.hex(32) }
    patreon_refresh_token { SecureRandom.hex(32) }
    enabled_as_sponsorable { true }

    trait :disabled_as_sponsorable do
      enabled_as_sponsorable { false }
    end

    trait :sponsor do
      disabled_as_sponsorable
      association :user, factory: [:user, :verified]
      enabled_as_sponsorable { false }
    end

    trait :with_tier do
      patreon_tier_count { 1 }
    end

    after(:create) do |spu, evaluator|
      if evaluator.patreon_tier_count > 0
        create_list(:sponsors_patreon_tier, evaluator.patreon_tier_count, sponsors_patreon_user: spu)
      end
    end
  end
end
