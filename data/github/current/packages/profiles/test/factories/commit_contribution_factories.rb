# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :commit_contribution do
    repository
    user
    committed_date { 1.day.from_now.to_date }
    commit_count { 5 }
  end
end
