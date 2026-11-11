# frozen_string_literal: true

FactoryBot.define do
  factory :tenant do
    sequence(:github_id, 1001)
    slug { "staffship-01" }
    shortcode { "abc" }
  end
end
