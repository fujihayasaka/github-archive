# typed: strict
# frozen_string_literal: true

module Billing
  module UsageDependency
    extend ActiveSupport::Concern
    extend T::Helpers

    abstract!

    USAGE_REPORT_PERIOD_TODAY = 0
    USAGE_REPORT_PERIOD_THIS_MONTH = 1
    USAGE_REPORT_PERIOD_LAST_MONTH = 2
    USAGE_REPORT_PERIOD_THIS_YEAR = 3
    USAGE_REPORT_PERIOD_LAST_YEAR = 4
    USAGE_REPORT_LEGACY = 5
    USAGE_REPORT_CUSTOM_RANGE = 6

    MEUSE_REPORT_WINDOW = 180

    # Usage report types
    USAGE_REPORT_DETAILED_TYPE = 0
    USAGE_REPORT_SUMMARIZED_TYPE = 1
    USAGE_REPORT_LEGACY_TYPE = 2

    # Valid report types for validation
    VALID_REPORT_TYPES = T.let([USAGE_REPORT_DETAILED_TYPE, USAGE_REPORT_SUMMARIZED_TYPE, USAGE_REPORT_LEGACY_TYPE].freeze, T::Array[Integer])

    # Maximum days for custom range reports
    MAX_DETAILED_REPORT_DAYS = 31
    MAX_SUMMARIZED_REPORT_DAYS = 366

    sig { params(period: Integer).returns(T::Boolean) }
    def is_legacy_report?(period)
      period == USAGE_REPORT_LEGACY
    end

    sig { params(period: Integer).returns(T::Boolean) }
    def is_custom_range?(period)
      period == USAGE_REPORT_CUSTOM_RANGE
    end

    sig { returns(DateTime) }
    def get_start_date_for_legacy_period
      (Time.now.utc - MEUSE_REPORT_WINDOW.days).to_datetime
    end

    sig { returns({ type: Integer, displayText: String, dateText: String }) }
    def usage_report_legacy_selection
      { type: USAGE_REPORT_LEGACY, displayText: "Legacy usage", dateText: "" }
    end

    sig { returns({ type: Integer, displayText: String, dateText: String }) }
    def usage_report_custom_range_selection
      { type: USAGE_REPORT_CUSTOM_RANGE, displayText: "Custom Range", dateText: "" }
    end

    sig { returns(T::Array[{ type: Integer, displayText: String, dateText: String }]) }
    def usage_report_selections
      [
        { type: USAGE_REPORT_PERIOD_TODAY, displayText: "Today", dateText: Date.today.strftime("%B %-d, %Y") },
        { type: USAGE_REPORT_PERIOD_THIS_MONTH, displayText: "Current month", dateText: Date.today.strftime("%B %Y") },
        { type: USAGE_REPORT_PERIOD_LAST_MONTH, displayText: "Last month", dateText: 1.month.ago.strftime("%B %Y") },
        { type: USAGE_REPORT_PERIOD_THIS_YEAR, displayText: "This year", dateText: Time.now.utc.year.to_s },
        { type: USAGE_REPORT_PERIOD_LAST_YEAR, displayText: "Last year", dateText: (Time.now.utc.year - 1).to_s },
        { type: USAGE_REPORT_CUSTOM_RANGE, displayText: "Custom range", dateText: "Up to 31 days" }
      ]
    end

    sig { returns(T::Array[{ type: Integer, displayText: String, dateText: String }]) }
    def usage_report_common_period_selections
      [
        { type: USAGE_REPORT_PERIOD_TODAY, displayText: "Today", dateText: Date.today.strftime("%B %-d, %Y") },
        { type: USAGE_REPORT_PERIOD_THIS_MONTH, displayText: "Current month", dateText: Date.today.strftime("%B %Y") },
      ]
    end

    sig do
      params(
        is_legacy_option: T::Boolean,
        migration_date: T.nilable(String),
        min_custom_date: Date
      ).returns(T::Array[{ type: Integer, displayText: String, dateText: String }])
    end
    def usage_report_type_selections(is_legacy_option:, migration_date:, min_custom_date:)
      common_selections = usage_report_common_period_selections
      if min_custom_date < 1.month.ago.utc.end_of_month
        common_selections << { type: USAGE_REPORT_PERIOD_LAST_MONTH, displayText: "Last month", dateText: 1.month.ago.strftime("%B %Y") }
      end

      selections = [
        {
          type: USAGE_REPORT_SUMMARIZED_TYPE,
          displayText: "Summarized",
          dateText: "Metered usage by repository for up to 1 year",
          usagePeriods: common_selections + [
            { type: USAGE_REPORT_PERIOD_THIS_YEAR, displayText: "This year", dateText: Time.now.utc.year.to_s },
            { type: USAGE_REPORT_CUSTOM_RANGE, displayText: "Custom range", dateText: "Up to 1 year" }
          ]
        },
        {
          type: USAGE_REPORT_DETAILED_TYPE,
          displayText: "Detailed",
          dateText: "Metered usage by username and workflow for up to 31 days",
          usagePeriods: common_selections + [
            { type: USAGE_REPORT_CUSTOM_RANGE, displayText: "Custom range", dateText: "Up to #{MAX_DETAILED_REPORT_DAYS} days" }
          ]
        }
      ]

      if is_legacy_option && migration_date
        selections << { type: USAGE_REPORT_LEGACY_TYPE, displayText: "Legacy", dateText: "Metered usage before the billing transition, until #{migration_date}", usagePeriods: [] }
      end

      selections
    end

    sig { params(period: Integer, start_date: T.nilable(String)).returns(Time) }
    def get_start_date_for_period(period, start_date: nil)
      case period
      when USAGE_REPORT_PERIOD_TODAY
        DateTime.now.utc.beginning_of_day
      when USAGE_REPORT_PERIOD_THIS_MONTH
        DateTime.now.utc.beginning_of_month
      when USAGE_REPORT_PERIOD_LAST_MONTH
        1.month.ago.utc.beginning_of_month
      when USAGE_REPORT_PERIOD_THIS_YEAR
        DateTime.now.utc.beginning_of_year
      when USAGE_REPORT_PERIOD_LAST_YEAR
        1.year.ago.utc.beginning_of_year
      when USAGE_REPORT_CUSTOM_RANGE
        DateTime.parse(start_date).utc.beginning_of_day
      end
    end

    sig { params(customer: Customer).returns(DateTime) }
    def get_end_date_for_legacy_period(customer)
      end_date = customer.vnext_migration_date&.to_datetime || DateTime.now.utc
      [end_date, DateTime.now.yesterday.utc].min.to_datetime # because of 1 day delay of DW data, yesterday is the latest date we can query
    end

    sig { params(period: Integer, end_date: T.nilable(String)).returns(Time) }
    def get_end_date_for_period(period, end_date: nil)
      end_date = case period
      when USAGE_REPORT_PERIOD_TODAY
        DateTime.now.utc.end_of_day
      when USAGE_REPORT_PERIOD_THIS_MONTH
        DateTime.now.utc.end_of_month
      when USAGE_REPORT_PERIOD_LAST_MONTH
        1.month.ago.utc.end_of_month
      when USAGE_REPORT_PERIOD_THIS_YEAR
        DateTime.now.utc.end_of_year
      when USAGE_REPORT_PERIOD_LAST_YEAR
        1.year.ago.utc.end_of_year
      when USAGE_REPORT_CUSTOM_RANGE
        DateTime.parse(end_date).utc.end_of_day
      end

      now = DateTime.now.utc
      end_date <= now ? end_date : now
    end

    sig { params(business: Business).returns(T.nilable(T::Boolean)) }
    def migrated_meuse_customer?(business)
      business.customer&.billing_platform_enabled_product&.migration_date?
    end

    sig do params(selections: T::Array[{ type: Integer, displayText: String, dateText: String }], migration_date: Time).returns(
      T::Array[{ type: Integer, displayText: String, dateText: String }])
    end
    def filter_period_selections(selections, migration_date)
      unless 1.year.ago.utc.all_year.include?(migration_date)
        selections.select! do |selection|
          selection[:type] != USAGE_REPORT_PERIOD_LAST_YEAR
        end
      end

      unless migration_date < 1.month.ago.utc.end_of_month
        selections.select! do |selection|
          selection[:type] != USAGE_REPORT_PERIOD_LAST_MONTH
        end
      end

      selections
    end

    sig { params(start_date: T.nilable(String), end_date: T.nilable(String), entity: ::Billing::Types::Account, type: Integer).returns(T::Boolean) }
    def is_custom_range_valid?(start_date:, end_date:, entity:, type:)
      return false if start_date.blank? || end_date.blank?

      start_date = DateTime.parse(start_date).utc.beginning_of_day.to_date
      end_date = DateTime.parse(end_date).utc.end_of_day.to_date

      case type
      when USAGE_REPORT_DETAILED_TYPE
        return false if (end_date - start_date + 1).to_i > MAX_DETAILED_REPORT_DAYS
      when USAGE_REPORT_SUMMARIZED_TYPE
        return false if (end_date - start_date + 1).to_i > MAX_SUMMARIZED_REPORT_DAYS
      end
      start_date >= min_custom_date(customer: T.must(entity.customer))
    end

    sig { params(billable_owner: T.any(User, Business)).returns(Integer) }
    def billable_owner_type(billable_owner)
      case billable_owner
      when Business
        ::BillingPlatform::Api::V1::BillableOwnerType::Business
      when User
        ::BillingPlatform::Api::V1::BillableOwnerType::User
      end
    end

    sig { params(customer: Customer).returns(Date) }
    def min_custom_date(customer:)
      two_years_ago = 2.years.ago.to_date
      # Determine how far back a vnext native customer can request data for, either 2 years ago or their creation date, whichever is more recent
      return [customer.created_at.to_date, two_years_ago].compact.max if customer.is_vnext_native?

      # Determine how far back a migrated customer can request data for, either 2 years ago or their migration date, whichever is more recent
      migration_date = customer.vnext_migration_date&.to_date
      [migration_date, two_years_ago].compact.max
    end

    sig { params(entity: ::Billing::Types::Account, payload: T::Hash[Symbol, ::Billing::Types::Account]).void }
    def add_entity_to_payload(entity:, payload:)
      case entity
      when Business
        payload[:business] = entity
      when Organization
        payload[:org] = entity
      when User
        payload[:user] = entity
      end
    end
  end
end
