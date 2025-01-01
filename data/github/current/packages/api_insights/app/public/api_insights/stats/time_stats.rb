# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  class TimeStats < StatsBase
    extend T::Helpers
    include RequestorFilterable

    sig { params(organization_id: Integer, min_timestamp: Time, max_timestamp: Time, timestamp_increment: String).void }
    def initialize(organization_id, min_timestamp, max_timestamp, timestamp_increment)
      super organization_id, min_timestamp, max_timestamp
      query.timestamp_increment_summary_key = Queries::TimestampIncrementSummaryKey.new(timestamp_increment)
      query.sort_definitions << Queries::SortDefinition.new(Queries::SortField::Timestamp)
    end

    private

    sig { override.params(sort_field: Queries::SortField).returns(T::Boolean) }
    def valid_sort_field?(sort_field)
      return true if super sort_field

      sort_field == Queries::SortField::Timestamp
    end
  end
end
