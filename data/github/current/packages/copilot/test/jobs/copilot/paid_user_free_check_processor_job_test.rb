# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/missing_record_helper"

class CopilotPaidUserFreeCheckProcessorJobTest < GitHub::TestCase
  include CopilotTestHelper
  include GitHub::LoggerHelper
  include JobTestHelper
  include MissingRecordHelper

  setup do
    @copilot_monthly_product_uuid =
      create(:billing_product_uuid, :copilot, :monthly)
    @copilot_yearly_product_uuid =
      create(:billing_product_uuid, :copilot, :yearly)

    enable_feature_flag(:copilot_paid_user_free_check_job)
    enable_feature_flag(:copilot_paid_user_free_check_job_refund)
    enable_feature_flag(:copilot_chatterbox)
  end

  test "skips without feature flag" do
    disable_feature_flag(:copilot_paid_user_free_check_job)

    logs = capture_logs do
      assert_performed_jobs 0 do
        Copilot::PaidUserFreeCheckProcessorJob.perform_now([1])
      end
    end

    assert_includes logs, "Skipping Copilot::PaidUserFreeCheckProcessorJob"
  end

  test "logs an error with no subscription item found" do
    subscription_item = missing(:billing_subscription_item)

    logs = capture_logs do
      assert_performed_jobs 0 do
        Copilot::PaidUserFreeCheckProcessorJob.perform_now(
          [subscription_item.id],
        )
      end
    end

    assert_includes logs, "Performing Copilot::PaidUserFreeCheckProcessorJob"
    assert_includes logs, "No SubscriptionItem found"
    assert_log_match logs,
      "gh.billing.subscription_item.id",
      subscription_item.id
  end

  test "does nothing when the user is not a free user" do
    subscription_item = create(
      :billing_subscription_item,
      :paid,
      subscribable: @copilot_monthly_product_uuid
    )

    CopilotFreeUserMailer
      .expects(:paid_user_became_free)
      .never

    ::Billing::Public::SubscriptionItem
      .expects(:cancel_and_refund)
      .never

    logs = capture_logs do
      Copilot::PaidUserFreeCheckProcessorJob.perform_now(
        [subscription_item.id],
      )
    end

    assert_includes logs, "Performing Copilot::PaidUserFreeCheckProcessorJob"
    assert_includes logs, "User is nominal"
    assert_log_match logs, "gh.user.id", subscription_item.user.id
  end

  test "performs a dry run if the feature flag is not enabled" do
    disable_feature_flag(:copilot_paid_user_free_check_job_refund)

    subscription_item = create(
      :billing_subscription_item,
      :paid,
      subscribable: @copilot_monthly_product_uuid
    )

    free_user = create(
      :copilot_free_user,
      :educational,
      user: subscription_item.user,
    )

    CopilotFreeUserMailer
      .expects(:paid_user_became_free)
      .never

    ::Billing::CancelAndRefundSubscriptionItemJob
      .expects(:perform_later)
      .never

    logs = capture_logs do
      Copilot::PaidUserFreeCheckProcessorJob.perform_now(
        [subscription_item.id],
      )
    end

    assert free_user.reload.subscribed?,
      "sets the free user to subscribed"
    assert free_user.reload.subscribed_at,
      "uses the #subscribe method to set the timestamp"

    assert_includes logs, "Performing Copilot::PaidUserFreeCheckProcessorJob"
    assert_includes logs, "Found FreeUser, would refund"

    assert_log_match logs,
      "gh.copilot.free_user.free_user_type",
      free_user.free_user_type

    assert_log_match logs,
      "gh.copilot.free_user.subscribed",
      "false"

    assert_log_match logs,
      "gh.copilot.free_user.id",
      free_user.id

    assert_log_match logs,
      "gh.user.id",
      subscription_item.user.id
  end

  test "refunds and emails free users" do
    subscription_item_1 = create(
      :billing_subscription_item,
      :paid,
      subscribable: @copilot_monthly_product_uuid
    )

    subscription_item_2 = create(
      :billing_subscription_item,
      :paid,
      subscribable: @copilot_monthly_product_uuid
    )

    free_user_1 = create(
      :copilot_free_user,
      :educational,
      user: subscription_item_1.user,
    )

    free_user_2 = create(
      :copilot_free_user,
      :ms_mvp,
      user: subscription_item_2.user,
    )

    CopilotFreeUserMailer
      .expects(:paid_user_became_free)
      .with(subscription_item_1.user)
      .returns(mock.tap { |m| m.expects(:deliver_later).once })
      .once

    CopilotFreeUserMailer
      .expects(:paid_user_became_free)
      .with(subscription_item_2.user)
      .returns(mock.tap { |m| m.expects(:deliver_later).once })
      .once

    ::Billing::CancelAndRefundSubscriptionItemJob
      .expects(:perform_later)
      .times(2)

    logs = capture_logs do
      Copilot::PaidUserFreeCheckProcessorJob.perform_now(
        [subscription_item_1.id, subscription_item_2.id],
      )
    end

    assert free_user_1.reload.subscribed?,
      "sets the free user to subscribed"
    assert free_user_2.reload.subscribed?,
      "sets the free user to subscribed"

    assert free_user_1.reload.subscribed_at,
      "uses the #subscribe method to set the timestamp"
    assert free_user_2.reload.subscribed_at,
      "uses the #subscribe method to set the timestamp"

    assert_includes logs, "Performing Copilot::PaidUserFreeCheckProcessorJob"
    assert_includes logs, "Found FreeUser, refunding"

    assert_log_match logs,
      "gh.copilot.free_user.free_user_type",
      free_user_1.free_user_type
    assert_log_match logs,
      "gh.copilot.free_user.free_user_type",
      free_user_2.free_user_type

    assert_log_match logs,
      "gh.copilot.free_user.subscribed",
      "false"

    assert_log_match logs,
      "gh.copilot.free_user.id",
      free_user_1.id
    assert_log_match logs,
      "gh.copilot.free_user.id",
      free_user_2.id

    assert_log_match logs,
      "gh.user.id",
      subscription_item_1.user.id
    assert_log_match logs,
      "gh.user.id",
      subscription_item_2.user.id

    assert_log_match logs,
      "gh.chatterbox.message",
      "Refunded 2 users: #{subscription_item_1.user.id}, #{subscription_item_2.user.id}"
  end

  test "cancels free users that previously in-app purchased subscriptions" do
    subscription_item = create(
      :billing_subscription_item,
      :paid,
      :iap,
      subscribable: @copilot_monthly_product_uuid
    )

    create(:copilot_free_user, :educational, user: subscription_item.user)

    Copilot::PaidUserFreeCheckProcessorJob.perform_now([subscription_item.id])

    perform_enqueued_jobs(only: [Billing::CancelAndRefundSubscriptionItemJob])

    assert subscription_item.reload.cancelled?
  end
end if GitHub.copilot_enabled?
