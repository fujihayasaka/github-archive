# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :profile_pin do
    profile
    transient { user { profile.user } }
    pinned_item { create(:repository, owner: user) }

    trait :gist do
      pinned_item { create(:gist, user: user) }
    end
  end
end
