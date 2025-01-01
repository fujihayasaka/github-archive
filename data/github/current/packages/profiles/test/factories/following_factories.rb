# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :following do
    user
    association :following, factory: :user
  end
end
