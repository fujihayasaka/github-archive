# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SubscriptionItemOrderField < Platform::Enums::Base
      description "Properties by which subscription item connections can be ordered."
      visibility :internal

      value "CREATED_AT", "Order subscription items by creation time", value: "created_at"
      value "UPDATED_AT", "Order subscription items by update time", value: "updated_at"
    end
  end
end
