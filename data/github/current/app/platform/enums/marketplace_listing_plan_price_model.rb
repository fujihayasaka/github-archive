# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MarketplaceListingPlanPriceModel < Platform::Enums::Base
      description "The possible pricing models for a Marketplace listing plan."
      visibility :internal

      value "FREE", "There is no charge to use the product.", value: "FREE"
      value "FLAT_RATE", "There is a flat monthly or annual fee to use the product.", value: "FLAT_RATE"
      value "PER_UNIT", "There is a monthly or annual fee charged per unit (eg. per user).", value: "per-unit"
      value "DIRECT_BILLING", "Billing is handled by the integrator's billing system.", value: "direct-billing"
    end
  end
end
