# typed: false
# frozen_string_literal: true

module MetricQuery::SingleModelColumn
  ##
  # Mixin module for extending AR scopes/relations
  module Bucketed
    # Groups and orders the query by the given column, using the custom SQL for
    # the given timespan. (Which determines hourly/daily/weekly bucketing)
    def bucketed_by(column, timespan)
      where(column => timespan.to_range)
        .group(timespan.group_by(column))
        .order(column)
    end

    # This is meant to be identical to bucketed_by above, but it omits the
    # grouping function because it is not supported by Vitess. Consumers can
    # chain the `tally_by_creation_date` below to mimic `bucketed_by...count`
    def bucketed_without_group(column, timespan)
      where(column => timespan.to_range)
        .order(column)
    end

    def tally_by_creation_date
      map { |row| row.created_at.to_date.beginning_of_day.to_i }.tally # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end
end
