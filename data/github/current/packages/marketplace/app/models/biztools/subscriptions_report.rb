# typed: true
# frozen_string_literal: true

module Biztools
  class SubscriptionsReport
    CSV_HEADERS = [
      "User Type",
      "Name",
      "Email",
      "Plan Name",
      "Price Interval",
      "Price",
    ].freeze

    attr_reader :listing

    def initialize(listing:)
      @listing = listing
    end

    def filename
      "#{listing.name}-subscription-user-details.csv"
    end

    def as_csv
      CSV.generate do |csv|
        csv << CSV_HEADERS

        csv_values.each do |subscription|
          csv << subscription
        end
      end
    end

    def csv_values
      subscription_items = listing.subscription_items

      GitHub::PrefillAssociations.prefill_batch_method(subscription_items, :billing_interval)

      subscription_items.map do |subscription|
        next unless subscription.user.present?
        [
          subscription.user.type,
          subscription.user.display_login,
          subscription.user.email,
          subscription.subscribable.name,
          subscription.billing_interval,
          subscription.price.format,
        ]
      end.compact
    end
  end
end
