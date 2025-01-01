# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats::Queries
  class SummaryFilters

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :has_rate_limited_requests

    sig { params(has_rate_limited_requests: T.nilable(T::Boolean)).void }
    def initialize(has_rate_limited_requests: T.let(nil, T.nilable(T::Boolean)))
      @has_rate_limited_requests = has_rate_limited_requests
    end
  end
end
