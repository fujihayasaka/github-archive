# typed: true
# frozen_string_literal: true
module Platform
  # Given a query and the query cost (Analyzers::QueryCoster) of this query,
  # Use an API throttler to check the cost against our rate limits, and increment
  # usage unless the limit has been reached.
  #
  # This object is meant to be added to the query context and used by the QueryCoster
  # Analyzer to mutate the limits.
  #
  # Post-query, this is used to extract the rate information and update headers,
  # logs, and anything that may need the current rates.
  class CostLimiter
    attr_reader :rate_limit, :configuration

    def initialize(configuration)
      @configuration = configuration

      # Initialize with current limits, so that queries that dont even
      # get to be analyzed still return the current limits
      @rate_limit = Api::ConfigThrottler.new(@configuration).check
    end

    # Compute and verify rate limits.
    # Returns true if the query should be rate limited
    def check(cost, rate_limit_request_query: false)
      should_rate_limit = false

      # Check rate without incrementing it
      throttler = Api::ConfigThrottler.new(@configuration, amount: cost)
      rate = throttler.check

      if !rate_limit_request_query
        if rate.at_limit? || rate.remaining < cost
          should_rate_limit = true
        else
          # Actually remove cost from limits
          rate = throttler.rate!
        end
      end

      @rate_limit = rate

      should_rate_limit
    end
  end
end
