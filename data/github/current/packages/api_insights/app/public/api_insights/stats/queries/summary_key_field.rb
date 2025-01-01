# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats::Queries
  class SummaryKeyField < T::Enum

    enums do
      ActorId = new
      ActorName = new
      ActorType = new
      SubjectId = new
      SubjectName = new
      SubjectType = new
      HttpMethod = new
      ApiRoute = new
      IntegrationId = new
      IntegrationIdWhenSubjectInstallation = new
      OauthApplicationId = new
    end

    sig { returns(String) }
    def to_s
      case self
      when ActorId then "actor_id"
      when ActorName then "actor_name"
      when ActorType then "actor_type"
      when SubjectId then "subject_id"
      when SubjectName then "subject_name"
      when SubjectType then "subject_type"
      when HttpMethod then "http_method"
      when ApiRoute then "api_route"
      when IntegrationId then "integration_id"
      when IntegrationIdWhenSubjectInstallation then "integration_id = iff(subject_type == \"installation\", integration_id, long(null))"
      when OauthApplicationId then "oauth_application_id"
      else
        T.absurd(self)
      end
    end
  end
end
