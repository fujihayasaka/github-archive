# typed: strict
# frozen_string_literal: true

module Copilot
  module Instrumentation
    module Limiter
      include Helpers

      # @param tracking_id [String] The tracking ID for the cache bust event
      # @param cache_type [Symbol] The cache type (:USER_CACHE or :ORG_CACHE)
      # @param billable_customer_id [Integer, nil] The customer ID for busting cache for all users in a customer
      sig { params(tracking_id: String, cache_type: Symbol, billable_customer_id: T.nilable(Integer)).void }
      def instrument_copilot_limiter_bust_cache(tracking_id:, cache_type:, billable_customer_id: nil)
        instrument(::Copilot::Events::COPILOT_LIMITER_BUST_CACHE, {
          cache_type: cache_type,
          tracking_id: tracking_id,
          billable_customer_id: billable_customer_id,
        })
      end
    end
  end
end
