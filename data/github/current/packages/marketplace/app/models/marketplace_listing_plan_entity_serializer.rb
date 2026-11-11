
# typed: true
# frozen_string_literal: true

module MarketplaceListingPlanEntitySerializer
  def self.serialize(entity)
    # nb: plans have monthly and annual pricing. Serialization here
    # assumes monthly
    {
      plan_id: entity.id,
      plan_name: entity.name,
      plan_price_cents: entity.monthly_price_in_cents,
      renewal_frequency: "MONTHLY",
      current_state: entity.current_state.name,
    }
  end
end
