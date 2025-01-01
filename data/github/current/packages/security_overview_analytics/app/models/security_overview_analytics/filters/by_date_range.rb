# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    # ByDateRange applies a date range to filter the insights query's data
    # down to a certain datespan
    class ByDateRange
      extend T::Sig
      include GitHub::Memoizer

      RANGE_TEMPLATE = "id BETWEEN %{start_date_key} AND %{end_date_key}"
      POINTS_TEMPLATE = "id IN (%{date_keys})"

      sig { params(from: ::Date, to: ::Date, table: T.nilable(String), max_datapoints: Integer).void }
      def initialize(from:, to:, table: nil, max_datapoints: 100)
        raise ArgumentError, "max_datapoints must be greater than 0" if max_datapoints < 1

        @from = from
        @to = to

        if to < from
          @from = to
          @to = from
        end

        @range_template = T.let(table.blank? ? RANGE_TEMPLATE : "#{table}.#{RANGE_TEMPLATE}", String)
        @points_template = T.let(table.blank? ? POINTS_TEMPLATE : "#{table}.#{POINTS_TEMPLATE}", String)
        @max_datapoints = max_datapoints
      end

      sig { returns(String) }
      memoize def apply
        samples = []
        case sampling_period
        when :end
          samples = [@to]
        when :start_and_end
          samples = [@from, @to]
        when :daily
          return @range_template % { start_date_key: format_date(@from), end_date_key: format_date(@to) }
        when :weekly
          # Take days a week apart going backwards from @to date.
          # This will allow us to always include the @to date, not just full work weeks.
          samples = (@from..@to).select { |date| (@to - date).to_i.abs % 7 == 0 }
        when :monthly
          # If we can only fit monthly sampling, take first day of each month in the range.
          # This will exclude data from the 1st of the month up to the @to date and from the @from date till first of the next month.
          samples = (@from..@to).select { |date| date.day == 1 }
        else
          raise "Unsupported sampling period: #{sampling_period}"
        end

        samples.map! { |date| format_date(date) }
        @points_template % { date_keys: samples.join(", ") }
      end

      private

      sig { params(date: ::Date).returns(String) }
      def format_date(date)
        Date.id_from_date(date).to_s
      end

      sig { returns(Symbol) }
      memoize def sampling_period
        day_samples_count = (@to - @from).to_i + 1
        return :end if day_samples_count == 1 || @max_datapoints == 1
        return :daily if day_samples_count <= @max_datapoints

        week_samples_count = (day_samples_count / 7.0).ceil
        return :weekly if week_samples_count <= @max_datapoints && week_samples_count > 1

        month_samples_count = (@to.year * 12 + @to.month) - (@from.year * 12 + @from.month)
        # Ignores days, so a 'from' of Jan 31 and 'to' of Feb 01 would evaluate to 1 month.
        # We need to add 1 if 'from' is on the first of the month so a range like Jan 01 to Feb 01 will be 2 months.
        month_samples_count += 1 if @from.day == 1

        return :monthly if month_samples_count <= @max_datapoints && month_samples_count > 1

        :start_and_end
      end
    end
  end
end
