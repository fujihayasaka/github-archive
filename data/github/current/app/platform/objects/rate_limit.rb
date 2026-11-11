# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RateLimit < Platform::Objects::Base
      description "Represents the client's rate limit."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      #
      # Doesn't require special checks here as we have the
      # scopeless_tokens_as_minimum check which just requires
      # the token to be valid
      def self.async_api_can_access?(permission, obj)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      #
      # Doesn't require special checks here as we have the
      # scopeless_tokens_as_minimum check which just requires
      # the token to be valid
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :limit, Integer, method: :max_tries, description: "The maximum number of points the client is permitted to consume in a 60 minute window.", null: false

      field :cost, Integer, description: "The point cost for the current query counting against the rate limit.", null: false

      def cost
        @context[:cost_total]
      end

      field :remaining, Integer, description: "The number of points remaining in the current rate limit window.", null: false

      def remaining
        # If we're at 5 remaining out of 5,000 and the next request is 10,
        # don't return -5 since the next request will be rate limited.
        [0, @object.remaining].max
      end

      field :used, Integer, null: false,
        description: "The number of points used in the current rate limit window.",
        method: :tries

      field :reset_at, Scalars::DateTime, method: :expires_at, description: "The time at which the current rate limit window resets in UTC epoch seconds.", null: false

      field :cost_breakdowns, [Objects::CostBreakdown], visibility: :internal, description: "Field-level breakdown of this query's cost", null: true

      def cost_breakdowns
        @context[:cost_breakdowns]
      end

      field :node_count_breakdowns, [Objects::NodeCountBreakdown], visibility: :internal, description: "Type-by-type breakdown of how many nodes this query may access", null: true

      def node_count_breakdowns
        @context[:node_count_breakdowns]
      end

      field :node_count, Integer, description: "The maximum number of nodes this query may return", null: false

      def node_count
        @context[:node_count_total]
      end
    end
  end
end
