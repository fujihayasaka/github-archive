# typed: true
# frozen_string_literal: true

require "elastomer/query_stats"

# TODO: This is a copy of app/api/limiters/search_elapsed_time.rb with some
# customizations for testing new limiting thresholds and strategies.
# Once we fine tune these settings we'll merge the files and deduplicate
# the logic.

# Create a new SearchElaspedTime cost-based rate limit. The query time is
# used as the cost factor. Each user can use up to `max` milliseconds of
# query time over each `ttl` period.
module Search
  module Limiters
    class SearchElapsedTime < Search::Limiters::RateLimiterBase
      CODE_SEARCH_COST_FACTOR = 3

      def at_limit?(actor_id, search_type, additional_tags = [])
        tags = ["search_type:#{key_safe(search_type)}"] +
          additional_tags
        key = key(actor_id, search_type)
        check_rate_limit(key, 0, tags)
      end

      def increment(actor_id, search_type, additional_tags = [])
        tags = ["search_type:#{key_safe(search_type)}"] +
          additional_tags
        key = key(actor_id, search_type)
        amount = cost(search_type)
        return unless amount > 0
        increment_rate_limit(key, amount, tags)
      end

      # Internal: Only used for tests
      def delete(actor_id, search_type)
        key = key(actor_id, search_type)
        delete_rate_limit(key)
      end

      private

      def code_search?(search_type)
        search_type.downcase == Search::Types::CODE.downcase
      end

      # The cost is the number of milliseconds this request has taken.
      def cost(search_type)
        # NOTE: When using Blackbird, there will be no cost because no Elasticsearch queries are made.
        # However, Blackbird handles its own rate limiting, so that's OK.
        cost = Elastomer::QueryStats.instance.time

        if code_search?(search_type)
          cost * CODE_SEARCH_COST_FACTOR
        else
          cost
        end
      end
    end
  end
end
