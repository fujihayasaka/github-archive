# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  class StatsBase
    extend T::Helpers

    abstract!

    MAX_TIME_RANGE = 2_678_400 # 31 days (31 * 24 * 60 * 60)

    sig { params(organization_id: Integer, min_timestamp: Time, max_timestamp: Time).void }
    def initialize(organization_id, min_timestamp, max_timestamp)
      raise Error.new(ErrorCode::TIMESTAMP_RANGE_NEGATIVE, min_timestamp:, max_timestamp:) if min_timestamp > max_timestamp
      raise Error.new(ErrorCode::TIMESTAMP_RANGE_TOO_LARGE, min_timestamp:, max_timestamp:, max_range_allowed: "31 days") if max_timestamp - min_timestamp > MAX_TIME_RANGE

      @query = T.let(Queries::Query.new(GitHub.api_insights_active_kusto_tabular_input), Queries::Query)
      @query.filters << Queries::Filter.new(Queries::FilterField::OrganizationId, organization_id)
      @query.filters << Queries::RangeFilter.new(Queries::FilterField::Timestamp, min_timestamp, max_timestamp)

      @query.summary_fields << Queries::SummaryField::TotalRequestCount
      @query.summary_fields << Queries::SummaryField::RateLimitedRequestCount
      @query.summary_fields << Queries::SummaryField::LastRequestTimestamp
      @query.summary_fields << Queries::SummaryField::LastRateLimitedTimestamp
    end

    sig { params(tenant_id: Integer).void }
    def with_tenant_id(tenant_id)
      @query.filters << Queries::Filter.new(Queries::FilterField::TenantId, tenant_id)
    end

    sig { returns(StatsResult) }
    def get
      # It's important to avoid any mysql queries in this method to avoid threading errors.
      # Note that this includes any feature flag checks.
      dataset = KustoClientProvider.kusto_client.query(GitHub.api_insights_kusto_database_name, @query.text, @query.parameters)
      StatsResult.new(dataset)
    end

    private

    sig { returns(Queries::Query) }
    attr_reader :query

    sig { params(sort_definitions: T::Array[Queries::SortDefinition]).void }
    def validate_sort_definitions(sort_definitions)
      sort_definitions.each do |sort_definition|
        raise Error.new(ErrorCode::INVALID_SORT_FIELD, field: sort_definition.field) unless valid_sort_field?(sort_definition.field)
      end
    end

    sig { overridable.params(sort_field: Queries::SortField).returns(T::Boolean) }
    def valid_sort_field?(sort_field)
      sort_field == Queries::SortField::TotalRequestCount ||
      sort_field == Queries::SortField::RateLimitedRequestCount ||
      sort_field == Queries::SortField::LastRequestTimestamp ||
      sort_field == Queries::SortField::LastRateLimitedTimestamp
    end
  end
end
