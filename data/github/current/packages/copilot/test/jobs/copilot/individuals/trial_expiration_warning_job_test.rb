# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/missing_record_helper"

class Copilot::Individuals::TrialExpirationWarningJobTest < GitHub::TestCase
  include CopilotTestHelper
  include GitHub::LoggerHelper
  include JobTestHelper

  fixtures do
    @copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, :monthly)
  end

  setup do
    GitHub.flipper[:copilot_individual_trial_expiration_email_job].enable
    @mailer = mock
    @mailer.stubs(:deliver_later)
  end

  def create_paid_subscription_item(days_remaining:, payment_type: "credit_card")
    subscription_item = create(:billing_subscription_item,
                               subscribable: @copilot_monthly_product_uuid,
                               free_trial_ends_on: days_remaining.days.from_now)
    create(:billing_transaction_line_item,
           subscribable: @copilot_monthly_product_uuid,
           user: subscription_item.user,
           quantity: 1,
           billing_transaction: create(:billing_transaction, payment_type: payment_type))
    subscription_item
  end

  def create_expiring_subscription_item(days_remaining:)
    subscription_item = create(:billing_subscription_item,
                               :cancelled,
                               subscribable: @copilot_monthly_product_uuid,
                               free_trial_ends_on: days_remaining.days.from_now)
    account = subscription_item.account
    change = create(:billing_pending_plan_change, user: account)
    create(:billing_pending_subscription_item_change,
           :cancellation,
           pending_plan_change: change,
           subscribable: subscription_item.subscribable,
           plan_subscription: account.plan_subscription)
    subscription_item
  end

  test "skips without feature flag" do
    GitHub.flipper[:copilot_individual_trial_expiration_email_job].disable

    logs = capture_logs do
      assert_performed_jobs 0 do
        Copilot::Individuals::TrialExpirationWarningJob.perform_now([1])
      end
    end

    assert_includes logs, "Skipping Copilot::Individuals::TrialExpirationWarningJob"
  end

  test "does not email spammy users" do
    freeze_time do
      credit_card_item = create_paid_subscription_item(days_remaining: 14)
      credit_card_item.user.mark_as_spammy

      CopilotForIndividualsMailer.expects(:scheduled_payment_reminder).never
      CopilotForIndividualsMailer.expects(:cancellation_reminder).never
      CopilotForIndividualsMailer.expects(:one_day_from_scheduled_payment).never
      CopilotForIndividualsMailer.expects(:one_day_from_cancellation).never

      logs = capture_logs do
        Copilot::Individuals::TrialExpirationWarningJob.perform_now([credit_card_item.id])
      end

      assert_includes logs, "Skipping cancellation emails for spammy user"
      assert_log_match logs, "gh.user.id", credit_card_item.user.id
    end
  end

  test "emails users that will be charged via credit card in two weeks" do
    freeze_time do
      credit_card_item = create_paid_subscription_item(days_remaining: 14)
      CopilotForIndividualsMailer
        .expects(:scheduled_payment_reminder)
        .with(credit_card_item.user, @copilot_monthly_product_uuid, "credit_card", credit_card_item.free_trial_ends_on, 14)
        .returns(@mailer)
        .once

      logs = capture_logs do
        Copilot::Individuals::TrialExpirationWarningJob.perform_now([credit_card_item.id])
      end

      assert_includes logs, "Sending two weeks from scheduled payment email"
      assert_log_match logs, "gh.user.id", credit_card_item.user.id
      assert_log_match logs, "gh.billing.product_uuid.id", @copilot_monthly_product_uuid.id
      assert_log_match logs, "gh.billing.billing_transaction.payment_type", "credit_card"
      assert_log_match logs, :subscription_items_count, 1
    end
  end

  test "emails users that will be charged via credit card in one week" do
    freeze_time do
      one_week_credit_card_item = create_paid_subscription_item(days_remaining: 7)
      CopilotForIndividualsMailer
        .expects(:scheduled_payment_reminder)
        .with(one_week_credit_card_item.user, @copilot_monthly_product_uuid, "credit_card", one_week_credit_card_item.free_trial_ends_on, 7)
        .returns(@mailer)
        .once

      logs = capture_logs do
        Copilot::Individuals::TrialExpirationWarningJob.perform_now([one_week_credit_card_item.id])
      end

      assert_includes logs, "Sending one week from scheduled payment email"
      assert_log_match logs, "gh.user.id", one_week_credit_card_item.user.id
      assert_log_match logs, "gh.billing.product_uuid.id", @copilot_monthly_product_uuid.id
      assert_log_match logs, "gh.billing.billing_transaction.payment_type", "credit_card"
      assert_log_match logs, :subscription_items_count, 1
    end
  end

  test "emails users that will be charged via paypal in one week" do
    freeze_time do
      one_week_paypal_item = create_paid_subscription_item(days_remaining: 7, payment_type: "paypal")
      CopilotForIndividualsMailer
        .expects(:scheduled_payment_reminder)
        .with(one_week_paypal_item.user, @copilot_monthly_product_uuid, "paypal", one_week_paypal_item.free_trial_ends_on, 7)
        .returns(@mailer)
        .once

      logs = capture_logs do
        Copilot::Individuals::TrialExpirationWarningJob.perform_now([one_week_paypal_item.id])
      end

      assert_includes logs, "Sending one week from scheduled payment email"
      assert_log_match logs, "gh.user.id", one_week_paypal_item.user.id
      assert_log_match logs, "gh.billing.product_uuid.id", @copilot_monthly_product_uuid.id
      assert_log_match logs, "gh.billing.billing_transaction.payment_type", "paypal"
      assert_log_match logs, :subscription_items_count, 1
    end
  end

  test "emails users that will have their free trial expire in one week" do
    freeze_time do
      one_week_expiring_item = create_expiring_subscription_item(days_remaining: 7)

      CopilotForIndividualsMailer
        .expects(:cancellation_reminder)
        .with(one_week_expiring_item.user, one_week_expiring_item.free_trial_ends_on)
        .returns(@mailer)
        .once

      logs = capture_logs do
        Copilot::Individuals::TrialExpirationWarningJob.perform_now([one_week_expiring_item.id])
      end

      assert_includes logs, "Sending one week from cancellation email"
      assert_log_match logs, "gh.user.id", one_week_expiring_item.user.id
      assert_log_match logs, :subscription_items_count, 1
    end
  end

  test "emails users that will have their free trial expire in two weeks" do
    freeze_time do
      expiring_item = create_expiring_subscription_item(days_remaining: 14)

      CopilotForIndividualsMailer
        .expects(:cancellation_reminder)
        .with(expiring_item.user, expiring_item.free_trial_ends_on)
        .returns(@mailer)
        .once

      logs = capture_logs do
        Copilot::Individuals::TrialExpirationWarningJob.perform_now([expiring_item.id])
      end

      assert_includes logs, "Sending two weeks from cancellation email"
      assert_log_match logs, "gh.user.id", expiring_item.user.id
      assert_log_match logs, :subscription_items_count, 1
    end
  end

  test "emails users that will be charged via credit card in one day" do
    freeze_time do
      one_day_credit_card_item = create_paid_subscription_item(days_remaining: 1)
      CopilotForIndividualsMailer
        .expects(:one_day_from_scheduled_payment)
        .with(one_day_credit_card_item.user, @copilot_monthly_product_uuid, "credit_card", one_day_credit_card_item.free_trial_ends_on)
        .returns(@mailer)
        .once

      logs = capture_logs do
        Copilot::Individuals::TrialExpirationWarningJob.perform_now([one_day_credit_card_item.id])
      end

      assert_includes logs, "Sending one day from scheduled payment email"
      assert_log_match logs, "gh.user.id", one_day_credit_card_item.user.id
      assert_log_match logs, "gh.billing.product_uuid.id", @copilot_monthly_product_uuid.id
      assert_log_match logs, "gh.billing.billing_transaction.payment_type", "credit_card"
      assert_log_match logs, :subscription_items_count, 1
    end
  end

  test "emails users that will be charged via paypal in one day" do
    freeze_time do
      one_day_paypal_item = create_paid_subscription_item(days_remaining: 1, payment_type: "paypal",)
      CopilotForIndividualsMailer
        .expects(:one_day_from_scheduled_payment)
        .with(one_day_paypal_item.user, @copilot_monthly_product_uuid, "paypal", one_day_paypal_item.free_trial_ends_on)
        .returns(@mailer)
        .once

      logs = capture_logs do
        Copilot::Individuals::TrialExpirationWarningJob.perform_now([one_day_paypal_item.id])
      end

      assert_includes logs, "Sending one day from scheduled payment email"
      assert_log_match logs, "gh.user.id", one_day_paypal_item.user.id
      assert_log_match logs, "gh.billing.product_uuid.id", @copilot_monthly_product_uuid.id
      assert_log_match logs, "gh.billing.billing_transaction.payment_type", "paypal"
      assert_log_match logs, :subscription_items_count, 1
    end
  end

  test "emails users that will have their free trial expire in one day" do
    freeze_time do
      one_day_expiring_item = create_expiring_subscription_item(days_remaining: 1)
      CopilotForIndividualsMailer
        .expects(:one_day_from_cancellation)
        .with(one_day_expiring_item.user)
        .returns(@mailer)
        .once

      logs = capture_logs do
        Copilot::Individuals::TrialExpirationWarningJob.perform_now([one_day_expiring_item.id])
      end

      assert_includes logs, "Sending one day from cancellation email"
      assert_log_match logs, "gh.user.id", one_day_expiring_item.user.id
      assert_log_match logs, :subscription_items_count, 1
    end
  end

  test "does nothing with users who's trials are not expiring in either 1 or 7 days" do
    freeze_time do
      zero_days_item = create_paid_subscription_item(days_remaining: 0)
      two_days_item = create_paid_subscription_item(days_remaining: 2)
      six_days_item = create_paid_subscription_item(days_remaining: 6)
      eight_days_item = create_paid_subscription_item(days_remaining: 8)

      CopilotForIndividualsMailer.expects(:scheduled_payment_reminder).never
      CopilotForIndividualsMailer.expects(:cancellation_reminder).never
      CopilotForIndividualsMailer.expects(:one_day_from_scheduled_payment).never
      CopilotForIndividualsMailer.expects(:one_day_from_cancellation).never

      logs = capture_logs do
        Copilot::Individuals::TrialExpirationWarningJob
          .perform_now([zero_days_item.id, two_days_item.id, six_days_item.id, eight_days_item.id])
      end

      assert_log_match logs, :subscription_items_count, 4
    end
  end

  test "handles non-trial" do
    freeze_time do
      off_trial_item = create_paid_subscription_item(days_remaining: 1)
      off_trial_item.reload
      off_trial_item.update(free_trial_ends_on: nil)
      assert off_trial_item.reload.free_trial_ends_on.nil?

      CopilotForIndividualsMailer.expects(:scheduled_payment_reminder).never
      CopilotForIndividualsMailer.expects(:cancellation_reminder).never
      CopilotForIndividualsMailer.expects(:one_day_from_scheduled_payment).never
      CopilotForIndividualsMailer.expects(:one_day_from_cancellation).never

      logs = capture_logs do
        Copilot::Individuals::TrialExpirationWarningJob
          .perform_now([off_trial_item.id])
      end

      assert_log_match logs, :subscription_items_count, 0
    end
  end
end if GitHub.copilot_enabled?
