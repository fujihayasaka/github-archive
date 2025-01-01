# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :commit_contribution_summary do
    user
    repository
    year { 2023 }
    counts { [1] }
  end
end
