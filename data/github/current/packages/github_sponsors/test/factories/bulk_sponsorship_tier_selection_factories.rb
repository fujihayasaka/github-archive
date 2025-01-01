# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :bulk_sponsorship_tier_selection do
    sponsor { create(:user) }
    sponsors_tier_ids do
      tier1 = create(:sponsors_tier, :approved_sponsors_listing, :one_time)
      tier2 = create(:sponsors_tier, :approved_sponsors_listing)
      [tier1.id, tier2.id]
    end
  end
end
