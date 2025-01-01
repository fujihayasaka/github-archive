# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :user_status do
    user
    emoji { "\u{1f600}" } # This is 😀 in native emoji
    message { "Writing tests" }

    trait :with_expiration do
      expires_at { 3.days.from_now }
    end
  end
end
