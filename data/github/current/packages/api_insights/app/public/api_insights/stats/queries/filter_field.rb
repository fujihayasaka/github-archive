# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats::Queries
  class FilterField < T::Enum

    enums do
      TenantId = new("tenant_id")
      OrganizationId = new("request_org_id")
      Timestamp = new("timestamp")
      ActorId = new("actor_id")
      ActorName = new("actor_name")
      ActorType = new("actor_type")
      SubjectId = new("subject_id")
      SubjectName = new("subject_name")
      SubjectType = new("subject_type")
      ApiRoute = new("api_route")

      # Summary filters
      RateLimitedRequestCount = new("rate_limited_request_count")
    end

    sig { returns(String) }
    def to_s
      serialize
    end
  end
end
