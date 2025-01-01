# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :email_role do
    association :email, factory: :user_email
    user { email.user }

    trait :hard_bouncing do
      role { "hard_bounce" }
    end

    trait :stealth do
      role { "stealth" }
    end
  end
end
