# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :profile_highlight do
    user
    highlight_type { 0 } # defaults to nasa_2020
    eligible { true }
    hidden { false }
  end
end
