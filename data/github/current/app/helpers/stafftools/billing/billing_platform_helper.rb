# typed: strict
# frozen_string_literal: true

require "github/memoizer"

module Stafftools::Billing
  module BillingPlatformHelper
    include GitHub::Memoizer

    sig { returns(T.any(T::Hash[T.untyped, T.untyped], ::Billing::Platform::Api::Error)) }
    memoize def fetch_pricings
      # Create a timestamp rounded to nearest 10 minutes
      timestamp = Time.now.utc.to_i / 600 * 600  # 600 seconds = 10 minutes
      cache_key = "stafftools_billing_pricings:#{timestamp}"
      pricing = ::Billing::Platform::Api::Client.new.get_all_pricing

      return pricing if pricing.is_a?(::Billing::Platform::Api::Error)

      GitHub.cache.fetch(cache_key, stats_key: "stafftools.billing.pricings") do
        pricing
      end
    end
  end
end
