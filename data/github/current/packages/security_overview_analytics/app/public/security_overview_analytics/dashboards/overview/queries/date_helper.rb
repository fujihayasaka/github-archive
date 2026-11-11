# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class DateHelper

          DAYS_PER_WEEK = 7

          # Calculate an array of date IDs, evenly spaced between a start and end date.
          sig { params(start_date: ::Date, end_date: ::Date).returns(T::Array[Integer]) }
          def self.interval_date_ids(start_date, end_date)
            return [] if end_date < start_date

            date_ids = [::SecurityOverviewAnalytics::Date.id_from_date(start_date)]

            total_days = (end_date - start_date).to_i
            full_weeks = total_days / DAYS_PER_WEEK
            extra_days = total_days % DAYS_PER_WEEK
            intervals = full_weeks == 0 ? extra_days : DAYS_PER_WEEK

            # Distribute extra days across later intervals.
            intervals
              .times
              .map { |i| full_weeks + (i < extra_days ? 1 : 0) }
              .reverse_each do |interval|
                # Calculate next date by adding the current interval to the previously-calculated date.
                next_date = ::Date.parse(date_ids.last.to_s) + interval
                date_ids << ::SecurityOverviewAnalytics::Date.id_from_date(next_date)
              end

            date_ids
          end
        end
      end
    end
  end
end
