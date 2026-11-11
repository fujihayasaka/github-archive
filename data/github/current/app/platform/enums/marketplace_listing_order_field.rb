# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MarketplaceListingOrderField < Platform::Enums::Base
      description "Properties by which listing connections can be ordered."
      visibility :internal

      value "ID", "Order listings by id", value: "id"
      value "UPDATED_AT", "Order listings by update time", value: "updated_at"
    end
  end
end
