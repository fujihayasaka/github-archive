# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CopilotPaidUserFreeCheckJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper

  setup do
    @copilot_monthly_product_uuid =
      create(:billing_product_uuid, :copilot, :monthly)
    @copilot_yearly_product_uuid =
      create(:billing_product_uuid, :copilot, :yearly)

    GitHub.flipper[:copilot_paid_user_free_check_job].enable
    GitHub.flipper[:copilot_chatterbox].enable
  end

  test "skips without feature flag" do
    GitHub.flipper[:copilot_paid_user_free_check_job].disable

    logs = capture_logs do
      assert_performed_jobs 0 do
        Copilot::PaidUserFreeCheckJob.perform_now
      end
    end

    assert_includes logs, "Skipping Copilot::PaidUserFreeCheckJob"
  end

  test "does nothing with no subscriptions" do
    logs = capture_logs do
      assert_performed_jobs 0 do
        Copilot::PaidUserFreeCheckJob.perform_now
      end
    end

    assert_includes logs, "Performing Copilot::PaidUserFreeCheckJob"
    assert_includes logs, "Loaded ProductUUIDs"
    assert_log_match logs, "paid_users.count", 0
    assert_log_match logs, "gh.chatterbox.message",
      "Finished Copilot::PaidUserFreeCheckJob with 0 paid users"
  end

  test "enqueues processor jobs for monthly subscriptions" do
    subscription_item = create(
      :billing_subscription_item,
      :paid,
      subscribable: @copilot_monthly_product_uuid
    )

    logs = capture_logs do
      assert_enqueued_with(
        job: Copilot::PaidUserFreeCheckProcessorJob,
        args: [[subscription_item.id]],
      ) do
        assert_enqueued_with(
          job: Copilot::Individuals::TrialExpirationWarningJob,
          args: [[subscription_item.id]],
        ) do
          Copilot::PaidUserFreeCheckJob.perform_now
        end
      end
    end

    assert_includes logs, "Performing Copilot::PaidUserFreeCheckJob"
    assert_includes logs, "Loaded ProductUUIDs"
    assert_log_match logs, "paid_users.count", 1
    assert_log_match logs, "gh.chatterbox.message",
      "Finished Copilot::PaidUserFreeCheckJob with 1 paid users"
  end

  test "enqueues processor jobs for yearly subscriptions" do
    subscription_item = create(
      :billing_subscription_item,
      :paid,
      subscribable: @copilot_yearly_product_uuid
    )

    logs = capture_logs do
      assert_enqueued_with(
        job: Copilot::PaidUserFreeCheckProcessorJob,
        args: [[subscription_item.id]],
      ) do
        assert_enqueued_with(
          job: Copilot::Individuals::TrialExpirationWarningJob,
          args: [[subscription_item.id]],
        ) do
          Copilot::PaidUserFreeCheckJob.perform_now
        end
      end
    end

    assert_includes logs, "Performing Copilot::PaidUserFreeCheckJob"
    assert_includes logs, "Loaded ProductUUIDs"
    assert_log_match logs, "paid_users.count", 1
    assert_log_match logs, "gh.chatterbox.message",
      "Finished Copilot::PaidUserFreeCheckJob with 1 paid users"
  end

  test "does not enqueue inactive subscriptions" do
    create(
      :billing_subscription_item,
      :paid,
      quantity: 0, # Mark as inactive
      subscribable: @copilot_monthly_product_uuid
    )

    logs = capture_logs do
      assert_performed_jobs 0 do
        Copilot::PaidUserFreeCheckJob.perform_now
      end
    end

    assert_includes logs, "Performing Copilot::PaidUserFreeCheckJob"
    assert_includes logs, "Loaded ProductUUIDs"
    assert_log_match logs, "paid_users.count", 0
    assert_log_match logs, "gh.chatterbox.message",
      "Finished Copilot::PaidUserFreeCheckJob with 0 paid users"
  end
end if GitHub.copilot_enabled?
