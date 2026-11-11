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
    def should_limit(cost)
      # check rate limit status
      if @rate_limit.at_limit? || @rate_limit.remaining < cost || @rate_limit.remaining == 0
        return true
      end

      # If the cost is 0 and since we are not rate limited
      # we don't need to write the cost in redis and we can now do an early return
      if cost <= 0
        return false
      end

      @rate_limit = Api::ConfigThrottler.new(@configuration, amount: cost).rate!

      false
    end

    # This is called by the timeout middleware to penalize against the
    # client's rate limit if their request times out.
    def timeout(env)
      was_penalized_tag = false
      throttler = Api::ConfigThrottler.new(@configuration, amount: Platform::TIMEOUT_PENALTY_COST)
      new_rate = throttler.rate!
      @rate_limit = new_rate
      was_penalized_tag = true

      # Emit the timeout penalty metric
      GitHub.dogstats.increment(
          "limiters.graphql_timeout_penalty",
          tags: ["penalized:#{was_penalized_tag}"]
      )
    end
  end
end
