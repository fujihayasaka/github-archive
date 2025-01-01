# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :developer_program_membership do
    user
    association :actor, factory: :user
    support_email { Faker::Internet.email }
    website { "https://example.com" }
  end
end
