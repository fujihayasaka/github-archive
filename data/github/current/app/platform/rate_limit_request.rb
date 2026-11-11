# typed: true
# frozen_string_literal: true

module Platform
  # Before running a query, take a quick look at the root selections.
  # Handle two special rate-limit cases:
  # - If the query contains `rateLimit` _only_, don't charge the client for this request
  # - If the query contains `rateLimit(dryRun: true)`, calculate the rate limit
  #   cost for this query and return it, but don't evaluate the other fields.
  module RateLimitRequest
    module_function

    def before_query(query)
      # Only run this check on non-internal queries, and skip mutations
      return if query.context[:origin] == Platform::ORIGIN_INTERNAL || !query.query?

      # If this query contains `rateLimit(dryRun: true)`, then we aren't actually going to evaluate it
      is_dry_run = query.lookahead.selects?("rateLimit", arguments: { "dryRun" => true })
      is_rate_limit_only = if is_dry_run
        true
      else
        # If this query consists of _rate limit requests only_, we don't count it against their rate limit
        unique_selected_field_names = query.lookahead.selections.map(&:name)
        unique_selected_field_names == [:rate_limit]
      end

      # Now, update the system with what we found
      query.context[:query_tracker].rate_limit_request_query = is_rate_limit_only
      query.context[:rate_limit_dry_run] = is_dry_run
    end

    # Must be implemented
    def after_query(query)
    end

    module Trace
      def analyze_query(query:)
        # Only run this check on non-internal queries, and skip mutations
        if query.context[:origin] != Platform::ORIGIN_INTERNAL && query.query?

          # If this query contains `rateLimit(dryRun: true)`, then we aren't actually going to evaluate it
          is_dry_run = query.lookahead.selects?("rateLimit", arguments: { "dryRun" => true })
          is_rate_limit_only = if is_dry_run
            true
          else
            # If this query consists of _rate limit requests only_, we don't count it against their rate limit
            unique_selected_field_names = query.lookahead.selections.map(&:name)
            unique_selected_field_names == [:rate_limit]
          end

          # Now, update the system with what we found
          query.context[:query_tracker].rate_limit_request_query = is_rate_limit_only
          query.context[:rate_limit_dry_run] = is_dry_run
        end
        super
      end
    end
  end
end
