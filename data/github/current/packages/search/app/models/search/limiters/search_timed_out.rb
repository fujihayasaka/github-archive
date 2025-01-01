# typed: true
# frozen_string_literal: true

module Search
  module Limiters
    # This rate limiter is triggered when a user issues a query that
    # elasticsearch times out. Such queries are rare and usually poorly formed,
    # while taking up tremendous resources.
    # Once a user has tripped the limit, they will no longer
    # be able to issue searches for that type of resource for the remainder of the
    # limiter TTL.
    # Currently, this is only a binary operation, we are not limiting by the number of
    # timed out queries that elastomer performed, to prevent a users from being
    # rate limited for a single bad query, if it happens to hit multiple indexes.
    # This can be configured by updating the `cost` method.
    class SearchTimedOut < RateLimiterBase
      sig do
        override.params(
          actor_id: RateLimiterBase::RateLimitedEntity,
          search_type: RateLimiterBase::SearchType,
          additional_tags: RateLimiterBase::InstrumentedTags
        ).void
      end
      def increment(actor_id, search_type, additional_tags = [])
        search_type = search_type.downcase
        key_ = key(actor_id, search_type)
        cost_ = cost
        return unless cost_ > 0
        increment_rate_limit(key_, cost_, additional_tags)
      end

      sig { returns(Integer) }
      def cost
        Elastomer::QueryStats.timed_out? ? 1 : 0
      end

      sig do
        override.params(
          actor_id: RateLimiterBase::RateLimitedEntity,
          search_type: RateLimiterBase::SearchType,
          additional_tags: RateLimiterBase::InstrumentedTags
        ).returns(T::Boolean)
      end
      def at_limit?(actor_id, search_type, additional_tags = [])
        key_ = key(actor_id, search_type)
        check_rate_limit(key_, additional_tags)
      end
    end
  end
end
