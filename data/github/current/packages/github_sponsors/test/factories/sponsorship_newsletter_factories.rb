# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsorship_newsletter do
    author { create(:user) }
    sponsorable { create(:user, :sponsorable) }
    subject { Faker::Lorem.sentence }
    body { Faker::Lorem.paragraph }
    state { 0 }

    trait :draft do
      state { 0 }
    end

    trait :published do
      state { 1 }
    end

    trait :with_tier do
      transient do
        tier { nil }
      end

      after(:create) do |newsletter, evaluator|
        create(:sponsorship_newsletter_tier, sponsorship_newsletter: newsletter, tier: evaluator.tier)
      end
    end
  end
end
