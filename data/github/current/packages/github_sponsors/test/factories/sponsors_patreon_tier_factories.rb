# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsors_patreon_tier do
    sponsors_patreon_user
    sequence(:campaign_id) { |n| n.to_s }
    amount_in_cents { 1_00 }
  end
end
