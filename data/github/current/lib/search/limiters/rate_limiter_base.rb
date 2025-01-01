# typed: true
# frozen_string_literal: true

# A base factory class for Search::Limiters that will use RateLimiter for
# reading and writing limits from cache. Limiters that inherit from this class
# will still be responsible for calculating the cost of each request. The
# methods provided here make no assumptions about how subclasses will generate
# their cache keys.
module Search
  module Limiters
    class RateLimiterBase < Search::Limiters::Base
      include GitHub::RateLimitable

      def check_rate_limit(key, increment = 0, additional_tags = [])
        stat("limit_check", additional_tags)
        rate_limit_result = if increment.to_i > 0
          rate_limit_increment(key, { amount: increment.to_i }.merge(rate_limiter_options))
        else
          rate_limit_check(key, rate_limiter_options)
        end
        rate_limit_result.at_limit?
      end

      def increment_rate_limit(key, cost, additional_tags = [])
        stat("increment", additional_tags)
        rate_limit_increment(key, { amount: cost, ttl: ttl }).tries
      end

      # Internal: Only used for tests.
      def get_rate_limit(key)
        rate_limit_check(key).tries
      end

      # Internal: Only used for tests
      def delete_rate_limit(key)
        remove_rate_limit_key(key)
      end

      private

      def rate_limiter_options
        {
          max_tries: limit,
          ttl: ttl
        }
      end
    end
  end
end
