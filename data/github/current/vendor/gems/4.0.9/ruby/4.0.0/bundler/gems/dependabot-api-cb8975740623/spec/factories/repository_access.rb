# frozen_string_literal: true

FactoryBot.define do
  factory :repository_access do
    association :account
    sequence(:github_id, 10)
  end
end
