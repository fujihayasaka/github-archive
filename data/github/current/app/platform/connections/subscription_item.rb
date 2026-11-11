# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class SubscriptionItem < Connections::Base
      description "A list of subscription items."

      total_count_field

      field :total_monthly_price_in_cents, Integer, visibility: :under_development,
        description: "The total monthly cost for all subscription items in the connection, " \
          "in cents.", null: false

      def total_monthly_price_in_cents
        ::Billing::SubscriptionItem.async_total_monthly_price_in_cents(@object.items, include_fees: false)
      end
    end
  end
end
