# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :user_settings do
    settings { nil }
    association :user
  end
end
