# typed: true
# frozen_string_literal: true

require "test_helper"

module TradeCompliance::TradeScreening
  class SalesforceScreeningResultProcessorTest < GitHub::TestCase
    include HydroTestHelpers

    fixtures do
      skip unless GitHub.billing_enabled?

      @business = create(:business, :invoiced)
      @another_business = create(:business, :invoiced)
    end

    setup do
      @processor = SalesforceScreeningResultProcessor.new
    end

    def publish(message)
      hydro_publisher.publish(
        message,
        schema: "github.trade_screening.v0.SalesforceScreeningResult",
      )
    end

    def publish_and_consume(message)
      publish(message)
      yield
    end

    def create_message(enterprise_account_ids:, status:, request_time: Google::Protobuf::Timestamp.new(seconds: 1, nanos: 0))
      {
        enterprise_account_ids:,
        status:,
        request_time:,
      }
    end

    test "it does not process if enterprise_account_ids is blank" do
      refute @business.trade_screening_record.persisted?
      AccountScreeningProfile.any_instance.expects(:update).never

      publish_and_consume(create_message(enterprise_account_ids: [], status: "No Hit")) do
        run_processor(@processor, allowed_primary_query_count: 3)
      end

      @business.reload
      refute @business.trade_screening_record.persisted?
    end

    test "it does not process if screening status is blank" do
      refute @business.trade_screening_record.persisted?
      AccountScreeningProfile.any_instance.expects(:update).never

      publish_and_consume(create_message(enterprise_account_ids: [@business.id.to_s], status: "")) do
        run_processor(@processor, allowed_primary_query_count: 3)
      end

      @business.reload
      refute @business.trade_screening_record.persisted?
    end

    test "it does not process if request_time is blank" do
      refute @business.trade_screening_record.persisted?
      AccountScreeningProfile.any_instance.expects(:update).never

      message = create_message(
        enterprise_account_ids: [@business.id.to_s],
        status: "No Hit",
        request_time: nil
      )
      publish_and_consume(message) do
        run_processor(@processor, allowed_primary_query_count: 3)
      end

      @business.reload
      refute @business.trade_screening_record.persisted?
    end

    test "it does not process if screening status is invalid" do
      refute @business.trade_screening_record.persisted?
      AccountScreeningProfile.any_instance.expects(:update).never

      message = create_message(
        enterprise_account_ids: [@business.id.to_s],
        status: "No Match Found"
      )
      publish_and_consume(message) do
        run_processor(@processor, allowed_primary_query_count: 3)
      end

      sentry_error = Failbot.reports.last
      assert_match "Invalid screening status no_match_found for account #{@business.id}", Failbot.exception_message_from_hash(sentry_error)
      @business.reload
      refute @business.trade_screening_record.persisted?
    end

    test "it does not process any account that is not found" do
      Business.expects(:find_by).with(id: @business.id.to_s).returns(@business)
      Business.expects(:find_by).with(id: @business.id).returns(@business)
      Business.expects(:find_by).with(id: @another_business.id.to_s).returns(nil)

      refute @business.trade_screening_record.persisted?
      refute @another_business.trade_screening_record.persisted?

      message = create_message(
        enterprise_account_ids: [@business.id.to_s, @another_business.id.to_s],
        status: "Hit In Review"
      )
      publish_and_consume(message) do
        run_processor(@processor, allowed_primary_query_count: 2)
      end

      @business.reload
      assert @business.trade_screening_record.persisted?
      assert @business.trade_screening_record.hit_in_review?

      @another_business.reload
      refute @another_business.trade_screening_record.persisted?
    end

    test "it processes" do
      refute @business.trade_screening_record.persisted?

      publish_and_consume(create_message(enterprise_account_ids: [@business.id.to_s], status: "No Hit")) do
        run_processor(@processor, allowed_primary_query_count: 3)
      end

      @business.reload
      assert @business.trade_screening_record.persisted?
      assert @business.trade_screening_record.no_hit?
      refute_nil @business.trade_screening_record.last_trade_screen_date
    end
  end
end
