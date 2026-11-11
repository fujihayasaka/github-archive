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
    USAGE_REPORT_DETAILED_TYPE        = T.let(BillingPlatform::Api::V1::ReportType::Detailed, Integer)
    USAGE_REPORT_SUMMARIZED_TYPE      = T.let(BillingPlatform::Api::V1::ReportType::Summarized, Integer)
    USAGE_REPORT_LEGACY_TYPE          = T.let(BillingPlatform::Api::V1::ReportType::Legacy, Integer)
    USAGE_REPORT_PREMIUM_REQUEST_TYPE = T.let(BillingPlatform::Api::V1::ReportType::PremiumRequest, Integer)
    USAGE_REPORT_TOKEN_TYPE           = T.let(BillingPlatform::Api::V1::ReportType::Token, Integer)

    VALID_REPORT_TYPES = T.let([
      USAGE_REPORT_DETAILED_TYPE,
      USAGE_REPORT_SUMMARIZED_TYPE,
      USAGE_REPORT_LEGACY_TYPE,
      USAGE_REPORT_PREMIUM_REQUEST_TYPE
    ].freeze, T::Array[Integer])

    # All valid report types including feature-flagged types
    sig { params(entity: T.nilable(::Billing::Types::Account)).returns(T::Array[Integer]) }
    def valid_report_types(entity: nil)
      types = VALID_REPORT_TYPES.dup
      types << USAGE_REPORT_TOKEN_TYPE if FeatureFlag.vexi.enabled?(:billing_tbb_usage_report, entity, default: false)
      types
    end

    # Maximum days for custom range reports
    MAX_DETAILED_REPORT_DAYS = 31
    MAX_SUMMARIZED_REPORT_DAYS = 366
    MAX_PREMIUM_REQUEST_REPORT_DAYS = 31

    # TODO: Update to date we start receiving token usage data. Using this date for testing purposes.
    TOKEN_USAGE_LAUNCH_DATE = T.let(Date.new(2025, 12, 1), Date)

    sig { params(period: Integer).returns(T::Boolean) }
    def is_legacy_report?(period)
      period == USAGE_REPORT_LEGACY
    end

    sig { params(period: Integer).returns(T::Boolean) }
    def is_custom_range?(period)
      period == USAGE_REPORT_CUSTOM_RANGE
    end

    sig { returns(::Billing::Types::UsageReportSelection) }
    def usage_report_legacy_selection
      { type: USAGE_REPORT_LEGACY, displayText: "Legacy usage", dateText: "" }
    end

    sig { returns(::Billing::Types::UsageReportSelection) }
    def usage_report_custom_range_selection
      { type: USAGE_REPORT_CUSTOM_RANGE, displayText: "Custom Range", dateText: "" }
    end

    sig { returns(::Billing::Types::UsageReportSelections) }
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

    sig { returns(::Billing::Types::UsageReportSelections) }
    def premium_request_usage_report_selections
      current_time = Time.now.utc
      selections = [
        { type: USAGE_REPORT_PERIOD_TODAY, displayText: "Today", dateText: Date.today.strftime("%B %-d, %Y") },
        { type: USAGE_REPORT_PERIOD_THIS_MONTH, displayText: "Current month", dateText: Date.today.strftime("%B %Y") },
      ]

      # Only show "last month" if current month is greater than October 2025 since this is when billing premium request usage report data is available
      if current_time.year > 2025 || (current_time.year == 2025 && current_time.month >= 11)
        selections << { type: USAGE_REPORT_PERIOD_LAST_MONTH, displayText: "Last month", dateText: 1.month.ago.strftime("%B %Y") }
      end

      selections << { type: USAGE_REPORT_CUSTOM_RANGE, displayText: "Custom range", dateText: "Up to 31 days" }

      selections
    end

    sig { returns(::Billing::Types::UsageReportSelections) }
    def token_usage_report_selections
      premium_request_usage_report_selections.select { |period| token_usage_period_available?(period[:type]) }
    end

    sig { params(period_type: Integer).returns(T::Boolean) }
    def token_usage_period_available?(period_type)
      today = Time.now.utc.to_date
      return false if today < TOKEN_USAGE_LAUNCH_DATE

      case period_type
      when USAGE_REPORT_PERIOD_TODAY, USAGE_REPORT_PERIOD_THIS_MONTH, USAGE_REPORT_CUSTOM_RANGE
        true
      when USAGE_REPORT_PERIOD_LAST_MONTH
        last_month_end = today.beginning_of_month - 1.day
        TOKEN_USAGE_LAUNCH_DATE <= last_month_end
      else
        false
      end
    end

    sig { returns(::Billing::Types::UsageReportSelections) }
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
      ).returns(::Billing::Types::UsageReportSelections)
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

    sig { params(entity: T.nilable(::Billing::Types::Account)).returns(::Billing::Types::UsageReportTypeSelections) }
    def premium_request_usage_report_type_selections(entity: nil)
      selections = T.let([], ::Billing::Types::UsageReportTypeSelections)
      selections << {
        type: USAGE_REPORT_PREMIUM_REQUEST_TYPE,
        displayText: "Premium requests usage report",
        dateText: "Detailed per user breakdown of premium requests consumed",
        usagePeriods: premium_request_usage_report_selections
      }

      if FeatureFlag.vexi.enabled?(:billing_tbb_usage_report, entity, default: false)
        selections << {
          type: USAGE_REPORT_TOKEN_TYPE,
          displayText: "Token usage report",
          dateText: "Detailed token breakdown of premium requests consumed",
          usagePeriods: token_usage_report_selections
        }
      end

      selections
    end

    sig { params(business: Business).returns(T.nilable(T::Boolean)) }
    def migrated_meuse_customer?(business)
      business.customer&.billing_platform_enabled_product&.migration_date?
    end

    sig do params(selections: ::Billing::Types::UsageReportSelections, migration_date: Time).returns(
        ::Billing::Types::UsageReportSelections)
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
      when USAGE_REPORT_PREMIUM_REQUEST_TYPE, USAGE_REPORT_TOKEN_TYPE
        return false if (end_date - start_date + 1).to_i > MAX_PREMIUM_REQUEST_REPORT_DAYS
      else
        return false
      end

      min_start = min_custom_date(customer: T.must(entity.customer))
      min_start = [min_start, TOKEN_USAGE_LAUNCH_DATE].max if type == USAGE_REPORT_TOKEN_TYPE
      start_date >= min_start
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

    sig { params(customer: Customer, premium_request_report: T::Boolean).returns(Date) }
    def min_custom_date(customer:, premium_request_report: false)
      # Premium request usage reports powered by billing data are only available starting October 1, 2025
      # this conditional can be removed 2 years after that date (October 1, 2027)
      return Date.new(2025, 10, 1) if premium_request_report

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
