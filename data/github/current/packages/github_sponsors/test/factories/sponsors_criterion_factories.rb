# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsors_criterion do
    slug { "criterion_#{SecureRandom.hex(4)}" }
    description { Faker::Company.catch_phrase }

    trait :text do
      criterion_type { :text }
    end

    trait :member_reputable_org do
      slug { "member_reputable_org" }
      description { "The user is a member of an active or reputable GitHub organization" }
      automated { false }
      applicable_to { :user }
      active { true }
    end

    trait :objectionable_content do
      slug { "objectionable_content" }
      description { "A search for the user (Google, public website, Twitter) didn't result in any bigoted behavior" }
      automated { false }
      applicable_to { :all }
      active { true }
    end
  end
end
