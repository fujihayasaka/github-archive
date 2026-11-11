# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class Sponsorship < Connections::Base
      description "A list of sponsorships either from the subject or received by the subject."

      total_count_field

      field :total_recurring_monthly_price_in_cents, Integer, visibility: {
        internal: { environments: [:enterprise] },
        public: { environments: [:dotcom] },
      }, description: "The total amount in cents of all recurring sponsorships in the " \
        "connection whose amount you can view. Does not include one-time sponsorships.", null: false

      def total_recurring_monthly_price_in_cents
        ::Sponsorship.async_total_recurring_monthly_price_in_cents(@object.items,
          viewer: @context[:viewer])
      end

      field :total_recurring_monthly_price_in_dollars, Integer, visibility: {
        internal: { environments: [:enterprise] },
        public: { environments: [:dotcom] },
      }, description: "The total amount in USD of all recurring sponsorships in the connection " \
        "whose amount you can view. Does not include one-time sponsorships.", null: false

      def total_recurring_monthly_price_in_dollars
        ::Sponsorship.async_total_recurring_monthly_price_in_dollars(@object.items,
          viewer: @context[:viewer])
      end
    end
  end
end
