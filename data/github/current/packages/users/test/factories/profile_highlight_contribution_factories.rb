# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :profile_highlight_contribution do
    repository
    profile_highlight
    contributor_email { Sham.email }

    trait :ignored do
      ignore { true }
    end
  end
end
