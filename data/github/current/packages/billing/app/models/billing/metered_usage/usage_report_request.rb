# typed: strict
# frozen_string_literal: true

module Billing
  module MeteredUsage
    class UsageReportRequest

      class UsageReportPeriod < T::Enum
        enums do
          Today = new(0)
          ThisMonth = new(1)
          LastMonth = new(2)
          ThisYear = new(3)
          LastYear = new(4)
          Legacy = new(5)
          CustomRange = new(6)
        end
      end

      MEUSE_REPORT_WINDOW = 180

      sig { returns(::Billing::Types::Account) }
      attr_reader :entity

      sig { returns(Integer) }
      attr_reader :period

      sig { returns(T::Boolean) }
      attr_reader :is_stafftools

      sig { params(entity: ::Billing::Types::Account, period: Integer, start_date: T.nilable(Time), end_date: T.nilable(Time), is_stafftools: T::Boolean).void }
      def initialize(entity:, period:, start_date: nil, end_date: nil, is_stafftools: false)
        @entity = entity
        @start_date = start_date
        @end_date = end_date
        @period = period
        @is_stafftools = is_stafftools
      end

      sig { returns(Integer) }
      def start_date
        date = if is_custom_range?
          T.must(@start_date)
        elsif is_legacy_report?
          get_start_date_for_legacy_period
        else
          get_start_date_for_period
        end
        date.to_i
      end

      sig { returns(Integer) }
      def end_date
        date = if is_custom_range?
          T.must(@end_date)
        elsif is_legacy_report?
          get_end_date_for_legacy_period
        else
          get_end_date_for_period
        end
        date.to_i
      end

      sig { returns(T::Boolean) }
      def is_custom_range?
        period == UsageReportPeriod::CustomRange.serialize
      end

      sig { returns(T::Boolean) }
      def is_legacy_report?
        period == UsageReportPeriod::Legacy.serialize
      end

      private

      sig { returns(Time) }
      def get_start_date_for_period
        case period
        when UsageReportPeriod::Today.serialize
          DateTime.now.utc.beginning_of_day
        when UsageReportPeriod::ThisMonth.serialize
          DateTime.now.utc.beginning_of_month
        when UsageReportPeriod::LastMonth.serialize
          1.month.ago.utc.beginning_of_month
        when UsageReportPeriod::ThisYear.serialize
          DateTime.now.utc.beginning_of_year
        when UsageReportPeriod::LastYear.serialize
          1.year.ago.utc.beginning_of_year
        else
          raise ArgumentError, "Invalid period"
        end
      end

      sig { returns(Time) }
      def get_end_date_for_period
        end_date = case period
        when UsageReportPeriod::Today.serialize
          DateTime.now.utc.end_of_day
        when UsageReportPeriod::ThisMonth.serialize
          DateTime.now.utc.end_of_month
        when UsageReportPeriod::LastMonth.serialize
          1.month.ago.utc.end_of_month
        when UsageReportPeriod::ThisYear.serialize
          DateTime.now.utc.end_of_year
        when UsageReportPeriod::LastYear.serialize
          1.year.ago.utc.end_of_year
        when UsageReportPeriod::CustomRange.serialize
          @end_date
        end

        now = DateTime.now.utc
        end_date <= now ? end_date : now
      end

      sig { returns(DateTime) }
      def get_start_date_for_legacy_period
        # legacy report starts 180 days before today
        (Time.now.utc - MEUSE_REPORT_WINDOW.days).to_datetime
      end

      sig { returns(DateTime) }
      def get_end_date_for_legacy_period
        # legacy report ends on the day customer is migrated to vnext
        end_date = entity.customer&.vnext_migration_date&.to_datetime || DateTime.now.utc
        # because of 1 day delay of DW data, yesterday is the latest date we can query
        [end_date, DateTime.now.yesterday.utc].min.to_datetime
      end
    end
  end
end
