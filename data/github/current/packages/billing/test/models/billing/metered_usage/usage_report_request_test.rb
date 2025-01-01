# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::MeteredBilling
  class UsageReportRequestTest < GitHub::TestCase
    fixtures do
      @business = create :business, :with_self_serve_payment
      @customer = @business.customer
      @customer.update!(billed_via_billing_platform: true)
    end

    context "#start_date" do
      test "returns the correct start date for a custom range" do
        start_date = "2024-01-01".to_time
        end_date = "2024-01-31".to_time

        usage_report_request = Billing::MeteredUsage::UsageReportRequest.new(
          entity: @business,
          period: 6,
          start_date: start_date,
          end_date: end_date
        )

        assert_equal start_date.to_i, usage_report_request.start_date
      end

      test "returns the correct start date for a legacy report" do
        Timecop.freeze do
          @customer.update!(created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE - 1.day)
          create(:billing_platform_enabled_product, customer: @customer, migration_date: 30.days.ago)

          usage_report_request = Billing::MeteredUsage::UsageReportRequest.new(
            entity: @business,
            period: 5
          )

          expected_start_date = 180.days.ago.utc.to_i
          assert_equal expected_start_date, usage_report_request.start_date
        end
      end

      test "returns the correct start date for a today report" do
        usage_report_request = Billing::MeteredUsage::UsageReportRequest.new(
          entity: @business,
          period: 0
        )
        expected_start_date = DateTime.now.utc.beginning_of_day.to_i

        assert_equal expected_start_date, usage_report_request.start_date
      end
    end

    context "#end_date" do
      test "returns the correct end date for a custom range" do
        start_date = "2024-01-01".to_time
        end_date = "2024-01-31".to_time

        usage_report_request = Billing::MeteredUsage::UsageReportRequest.new(
          entity: @business,
          period: 6,
          start_date: start_date,
          end_date: end_date
        )

        assert_equal end_date.to_i, usage_report_request.end_date
      end

      test "returns yesterday as end date for a legacy report if customer is not migrated" do
        Timecop.freeze do
          usage_report_request = Billing::MeteredUsage::UsageReportRequest.new(
            entity: @business,
            period: 5,
          )
          expected_end_date = DateTime.now.yesterday.utc.to_datetime.to_i

          assert_equal expected_end_date, usage_report_request.end_date
        end
      end

      test "returns the correct end date for a this month report on the last day of a month" do
        Timecop.freeze(Time.utc(2024, 11, 30, 23, 59, 59)) do
          usage_report_request = Billing::MeteredUsage::UsageReportRequest.new(
            entity: @business,
            period: 1,
          )
          expected_end_date = DateTime.now.utc.end_of_month.to_i

          assert_equal expected_end_date, usage_report_request.end_date
        end
      end

      test "returns the correct end date for a this month report when it's not the last day of the month" do
        Timecop.freeze(Time.utc(2024, 11, 15, 23, 59, 59)) do
          usage_report_request = Billing::MeteredUsage::UsageReportRequest.new(
            entity: @business,
            period: 1,
          )
          expected_end_date = DateTime.now.utc.to_i
          assert_equal expected_end_date, usage_report_request.end_date
        end
      end

      test "returns the correct end date for a last month report" do
        Timecop.freeze(Time.utc(2024, 11, 15, 23, 59, 59)) do
          usage_report_request = Billing::MeteredUsage::UsageReportRequest.new(
            entity: @business,
            period: 2,
          )
          expected_end_date = 1.month.ago.utc.end_of_month.to_i
          assert_equal expected_end_date, usage_report_request.end_date
        end
      end

      test "returns the correct end date for a this year report" do
        Timecop.freeze(Time.utc(2024, 11, 15, 23, 59, 59)) do
          usage_report_request = Billing::MeteredUsage::UsageReportRequest.new(
            entity: @business,
            period: 3,
          )
          expected_end_date = DateTime.now.to_i
          assert_equal expected_end_date, usage_report_request.end_date
        end
      end

      test "returns the correct end date for a last year report" do
        Timecop.freeze(Time.utc(2024, 11, 15, 23, 59, 59)) do
          usage_report_request = Billing::MeteredUsage::UsageReportRequest.new(
            entity: @business,
            period: 4,
          )
          expected_end_date = 1.year.ago.utc.end_of_year.to_i
          assert_equal expected_end_date, usage_report_request.end_date
        end
      end
    end

    context "is_legacy_report?" do
      test "returns false when the period is not legacy" do
        usage_report_request = Billing::MeteredUsage::UsageReportRequest.new(
          entity: @business,
          period: 3
        )
        refute usage_report_request.is_legacy_report?
      end

      test "returns true when legacy" do
        usage_report_request = Billing::MeteredUsage::UsageReportRequest.new(
          entity: @business,
          period: 5
        )
        assert usage_report_request.is_legacy_report?
      end
    end
  end
end
