# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  class RouteStats < StatsBase
    extend T::Helpers
    include RequestorFilterable
    include RateLimitedSummaryFilterable
    include Sortable
    include Pageable

    sig { params(organization_id: Integer, min_timestamp: Time, max_timestamp: Time).void }
    def initialize(organization_id, min_timestamp, max_timestamp)
      super organization_id, min_timestamp, max_timestamp

      query.summary_key_fields << Queries::SummaryKeyField::HttpMethod
      query.summary_key_fields << Queries::SummaryKeyField::ApiRoute
    end

    sig { params(api_route_prefix: String).returns(T.self_type) }
    def with_api_route_prefix(api_route_prefix)
      query.filters << Queries::Filter.new(Queries::FilterField::ApiRoute, api_route_prefix, operator: "startswith")
      self
    end

    private

    sig { override.params(sort_field: Queries::SortField).returns(T::Boolean) }
    def valid_sort_field?(sort_field)
      return true if super sort_field

      sort_field == Queries::SortField::HttpMethod ||
      sort_field == Queries::SortField::ApiRoute
    end
  end
end
