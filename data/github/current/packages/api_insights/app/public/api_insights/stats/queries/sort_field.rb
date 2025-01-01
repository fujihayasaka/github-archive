# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats::Queries
  class SortField < T::Enum

    enums do
      # From SummaryField
      TotalRequestCount = new("total_request_count")
      RateLimitedRequestCount = new("rate_limited_request_count")
      LastRateLimitedTimestamp = new("last_rate_limited_timestamp")
      LastRequestTimestamp = new("last_request_timestamp")

      # From SummaryKeyField
      ActorId = new("actor_id")
      ActorName = new("actor_name")
      ActorType = new("actor_type")
      SubjectId = new("subject_id")
      SubjectName = new("subject_name")
      SubjectType = new("subject_type")
      HttpMethod = new("http_method")
      ApiRoute = new("api_route")
      IntegrationId = new("integration_id")
      OauthApplicationId = new("oauth_application_id")

      # From TimestampIncrementSummaryKey
      Timestamp = new("timestamp")
    end

    sig { returns(String) }
    def to_s
      serialize
    end
  end
end
