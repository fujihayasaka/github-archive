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
      extend T::Helpers
      include GitHub::RateLimitable

      RateLimitedEntity = T.type_alias { T.any(Integer, String) }
      SearchType = T.type_alias { T.any(Symbol, String) }
      InstrumentedTags = T.type_alias { T::Array[String] }

      sig { overridable.params(entity: RateLimitedEntity, search_type: SearchType, additional_tags: InstrumentedTags).returns(T::Boolean) }
      def at_limit?(entity, search_type, additional_tags)
        key_ = key(entity, search_type)
        check_rate_limit(key_, additional_tags)
      end

      # By default, this will get called at the end of every request. This out of the box behavior will always
      # increment with a cost of `1`; if that's not the behavior you want, you should override this method in
      # your subclassed rate limiter.
      sig { overridable.params(entity: RateLimitedEntity, search_type: SearchType, additional_tags: InstrumentedTags).void }
      def increment(entity, search_type, additional_tags)
        key_ = key(entity, search_type)
        increment_rate_limit(key_, 1, additional_tags)
      end

      sig { params(key: String, additional_tags: InstrumentedTags).returns(T::Boolean) }
      def check_rate_limit(key, additional_tags = [])
        stat("limit_check", additional_tags)
        rate_limit_check(key, rate_limiter_options).at_limit?
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
