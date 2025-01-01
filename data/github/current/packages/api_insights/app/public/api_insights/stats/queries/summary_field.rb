# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats::Queries
  class SummaryField < T::Enum

    enums do
      TotalRequestCount = new
      RateLimitedRequestCount = new
      LastRateLimitedTimestamp = new
      LastRequestTimestamp = new
    end

    sig { returns(String) }
    def to_s
      case self
      when TotalRequestCount
        then "total_request_count = sum(total_request_count)"
      when RateLimitedRequestCount
        then "rate_limited_request_count = sumif(rate_limited_request_count, is_primary_rate_limited)"
      when LastRateLimitedTimestamp
        then "last_rate_limited_timestamp = maxif(latest_request_timestamp, is_primary_rate_limited)"
      when LastRequestTimestamp
        then "last_request_timestamp = max(latest_request_timestamp)"
      else
        T.absurd(self)
      end
    end
  end
end
