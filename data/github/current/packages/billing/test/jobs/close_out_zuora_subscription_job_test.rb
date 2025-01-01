# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CloseOutZuoraSubscriptionJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include JobTestHelper
  include GitHub::ZuoraTestHelper

  fixtures do
    FakeZuora.mock

    @plan_subscription = create(:billing_plan_subscription, :zuora)
  end

  test "accepts optional collect_payment argument" do
    ::Billing::CloseZuoraSubscription
      .expects(:perform)
      .with(
        zuora_subscription_number: @plan_subscription.zuora_subscription_number,
        plan_subscription: @plan_subscription,
        collect_payment: true
      )
      .returns(GitHub::Billing::Result.success)

    CloseOutZuoraSubscriptionJob.perform_now(
      zuora_subscription_number: @plan_subscription.zuora_subscription_number,
      plan_subscription: @plan_subscription,
      collect_payment: true
    )
  end

  test "retries on timeout error" do
    ::Billing::CloseZuoraSubscription.stubs(:perform)
      .with(anything)
      .raises(Faraday::TimeoutError)
    Failbot.expects(:report).never

    assert_enqueued_jobs(1, only: CloseOutZuoraSubscriptionJob) do
      CloseOutZuoraSubscriptionJob.perform_now(
        zuora_subscription_number: @plan_subscription.zuora_subscription_number,
        plan_subscription: @plan_subscription,
      )
    end

    assert_dogstats_increment 1, "active_job.retry"
  end

  test "uses the ZuoraRateLimitHandler for too many requests error" do
    ::Billing::CloseZuoraSubscription.stubs(:perform)
      .with(anything)
      .raises(Zuorest::TooManyRequestsError.new("", {}, { "RateLimit-Reset" => "600" }))
    Failbot.expects(:report).never

    assert_enqueued_jobs(1, only: CloseOutZuoraSubscriptionJob) do
      CloseOutZuoraSubscriptionJob.perform_now(
        zuora_subscription_number: @plan_subscription.zuora_subscription_number,
        plan_subscription: @plan_subscription,
      )
    end

    assert_dogstats_increment 1, "billing.zuora_rate_limit_error", tags: ["class:close_out_zuora_subscription_job"]
  end

  test "reports to Failbot after max retries" do
    ::Billing::CloseZuoraSubscription.stubs(:perform)
      .with(anything)
      .raises(Faraday::TimeoutError)
    CloseOutZuoraSubscriptionJob.any_instance.stubs(:executions_for).returns(5)

    Failbot.expects(:report).once.with do |error|
      assert_equal Faraday::TimeoutError, error.class
      assert_equal "timeout", error.message
    end

    assert_enqueued_jobs(0, only: CloseOutZuoraSubscriptionJob) do
      CloseOutZuoraSubscriptionJob.perform_now(
        zuora_subscription_number: @plan_subscription.zuora_subscription_number,
        plan_subscription: @plan_subscription,
      )
    end
  end
end if GitHub.billing_enabled?
