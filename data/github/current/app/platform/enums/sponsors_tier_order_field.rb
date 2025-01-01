# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SponsorsTierOrderField < Platform::Enums::Base
      description "Properties by which Sponsors tiers connections can be ordered."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      value "CREATED_AT", "Order tiers by creation time.", value: "created_at"
      value "MONTHLY_PRICE_IN_CENTS", "Order tiers by their monthly price in cents", value: "monthly_price_in_cents"
    end
  end
end
