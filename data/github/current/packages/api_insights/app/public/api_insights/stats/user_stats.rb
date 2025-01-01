# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  class UserStats < StatsBase
    extend T::Helpers
    include RateLimitedSummaryFilterable
    include Sortable
    include Pageable

    sig { params(organization_id: Integer, min_timestamp: Time, max_timestamp: Time, user_id: Integer).void }
    def initialize(organization_id, min_timestamp, max_timestamp, user_id)
      super organization_id, min_timestamp, max_timestamp

      query.filters << Queries::Filter.new(Queries::FilterField::SubjectId, user_id)
      query.filters << Queries::Filter.new(Queries::FilterField::SubjectType, "user")

      query.summary_key_fields << Queries::SummaryKeyField::ActorType
      query.summary_key_fields << Queries::SummaryKeyField::ActorId
      query.summary_key_fields << Queries::SummaryKeyField::ActorName
      query.summary_key_fields << Queries::SummaryKeyField::IntegrationId
      query.summary_key_fields << Queries::SummaryKeyField::OauthApplicationId
    end

    sig { params(value: ActorType).returns(T.self_type) }
    def with_actor_type(value)
      query.filters << Queries::Filter.new(Queries::FilterField::ActorType, value.serialize)
      self
    end

    sig { params(actor_name_prefix: String).returns(T.self_type) }
    def with_actor_name_prefix(actor_name_prefix)
      query.filters << Queries::Filter.new(Queries::FilterField::ActorName, actor_name_prefix, operator: "startswith")
      self
    end

    private

    sig { override.params(sort_field: Queries::SortField).returns(T::Boolean) }
    def valid_sort_field?(sort_field)
      return true if super sort_field

      sort_field == Queries::SortField::ActorName
    end
  end
end
