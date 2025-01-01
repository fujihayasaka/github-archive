# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)


  trait :enterprise_managed_user_email do
    before(:create) do |user_email|
      email = user_email.email || Sham.email
      user_email.email = user_email.user.add_emu_shortcode_to_emails([email]).first
    end
  end

  factory :user_email, traits: TestEnv.test_with_all_emus? ? [:enterprise_managed_user_email] : [] do
    user
    email              { Sham.email }
    verification_token { SecureRandom.hex(20) }

    trait :verified do
      primary { true }
      state { "verified" }
      verified_at { 1.year.ago }
      verification_token { nil }
    end

    trait :launch_code do
      verification_token { "12345678" }
    end

    factory :verified_user_email, traits: [:verified]
  end
end
