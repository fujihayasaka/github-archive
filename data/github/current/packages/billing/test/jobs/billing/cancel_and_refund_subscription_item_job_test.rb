# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Billing::CancelAndRefundSubscriptionItemJobTest < GitHub::BillingTestCase
  include GitHub::ZuoraTestHelper
  include JobTestHelper
  include AuditLog::IntegrationTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @user = create(:credit_card_user, billed_on: GitHub::Billing.today + 1.month)
    @user.customer.update!(zuora_account_id: "8ad087d28c1ad866018c1cc9cd8c3637")

    # generated manually in zuora sandbox, record live response within a cassette
    @live_zuora_subscription_number = "A-S00105383"
    @live_zuora_subscription_id = "8ad093fb8c1aeb42018c1cca59262d7a"
    @live_zuora_transaction_id = "8ad08ad58c1ad876018c1ccb4dbc184b"
    @live_zuora_product_rate_plan_id = "8ad09bce828b63d901828d69e4a02b77"
  end

  setup do
    synchronize_github_products_to_zuora

    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    GitHub::Experiment.raise_on_mismatches = false
  end

  def setup_subscription_item_and_transaction(free_trial: false, start_date: GitHub::Billing.today, in_app_purchase: false)
    # copilot individual monthly product uuid
    copilot_product_uuid = Billing::ProductUUID.find_by(
      product_type: "github.copilot",
      product_key: "v0",
      billing_cycle: "month"
    )
    copilot_product_uuid&.zuora_product_rate_plan_id = @live_zuora_product_rate_plan_id
    copilot_product_uuid&.save!

    plan_subscription = create(
      :billing_plan_subscription,
      zuora_subscription_id: @live_zuora_subscription_id,
      zuora_subscription_number: @live_zuora_subscription_number,
      user: @user
    )

    billing_transaction = create(
      :billing_transaction,
      :zuora,
      plan_subscription: plan_subscription,
      user: @user,
      platform_transaction_id: @live_zuora_transaction_id,
      amount_in_cents: 1000,
      service_ends_at: start_date + 1.month,
    )

    create(
      :billing_transaction_line_item,
      billing_transaction: billing_transaction,
      subscribable: copilot_product_uuid,
      amount_in_cents: 1000,
      quantity: 0.1e1,
      description: "GitHub Copilot - month",
      service_start_date: start_date,
      service_end_date: start_date + 1.month,
    )

    arguments = {
      plan_subscription: plan_subscription,
      subscribable: copilot_product_uuid,
      free_trial_ends_on: free_trial ? start_date + 2.months : nil,
      quantity: 1
    }

    if in_app_purchase
      create(:billing_subscription_item, :iap, **arguments)
    else
      create(:billing_subscription_item, **arguments)
    end
  end

  test "cancels and performs a FULL refund of the subscription item" do
    subscription_item = setup_subscription_item_and_transaction(start_date: GitHub::Billing.today - 2.weeks)
    # ensure most recent transaction to copilot contains the full amount
    copilot_billing_transaction = Billing::BillingTransaction.for_user(@user).last
    assert_equal 1000, T.must(copilot_billing_transaction).amount_in_cents

    organization_id = 12345

    events = perform_audit_entries(only: "billing.subscription_item_cancel_and_refund") do
      with_live_zuora("zuora/cancel_and_fully_refund_copilot_for_individual") do
        result = ::Billing::CancelAndRefundSubscriptionItemJob.perform_now(
          subscription_item,
          organization_id: organization_id,
          full_refund: true
        )
        result = T.must(result)
        assert result.success?, result.error_message

        zuora_payment = Billing::Zuora::Payment.find(T.must(copilot_billing_transaction).platform_transaction_id)
        assert_equal 10, zuora_payment.refund_amount
      end
    end

    # subscription has been cancelled
    assert_equal 0, subscription_item.reload.quantity

    expected_payload = {
      organization_id: organization_id,
      payment_type: "credit_card",
      product_key: "v0",
      product_type: "github.copilot",
      refund_amount_in_cents: T.must(copilot_billing_transaction).amount_in_cents,
      cancelled: true,
      refund_result: "Success"
    }

    assert_subset_hash expected_payload, events.first
    assert_equal last_performed_audit_entries, events
  end

  test "cancels and refunds the subscription item" do
    subscription_item = setup_subscription_item_and_transaction
    # ensure most recent transaction to copilot contains the full amount
    copilot_billing_transaction = Billing::BillingTransaction.for_user(@user).last
    assert_equal 1000, T.must(copilot_billing_transaction).amount_in_cents

    organization_id = 12345

    events = perform_audit_entries(only: "billing.subscription_item_cancel_and_refund") do
      with_live_zuora("zuora/cancel_and_refund_copilot_for_individual") do
        result = ::Billing::CancelAndRefundSubscriptionItemJob.perform_now(
          subscription_item,
          organization_id: organization_id,
        )
        result = T.must(result)
        assert result.success?, result.error_message

        zuora_payment = Billing::Zuora::Payment.find(T.must(copilot_billing_transaction).platform_transaction_id)
        assert_equal 10, zuora_payment.refund_amount
      end
    end

    # subscription has been cancelled
    assert_equal 0, subscription_item.reload.quantity

    expected_payload = {
      organization_id: organization_id,
      payment_type: "credit_card",
      product_key: "v0",
      product_type: "github.copilot",
      refund_amount_in_cents: T.must(copilot_billing_transaction).amount_in_cents,
      cancelled: true,
      refund_result: "Success"
    }

    assert_subset_hash expected_payload, events.first
    assert_equal last_performed_audit_entries, events
  end

  test "cancels and refunds the subscription item that was partially paid by credit balance" do
    subscription_item = setup_subscription_item_and_transaction
    # ensure most recent transaction to copilot contains the full amount
    copilot_billing_transaction = Billing::BillingTransaction.for_user(@user).last
    assert_equal 1000, T.must(copilot_billing_transaction).amount_in_cents

    organization_id = 12345
    Billing::Zuora::Invoice.any_instance.stubs(:payment_amount).returns(6.0)

    events = perform_audit_entries(only: "billing.subscription_item_cancel_and_refund") do
      with_live_zuora("zuora/cancel_and_refund_copilot_for_individual") do
        result = ::Billing::CancelAndRefundSubscriptionItemJob.perform_now(
          subscription_item,
          organization_id: organization_id,
        )
        result = T.must(result)
        assert result.success?, result.error_message
      end
    end

    # subscription has been cancelled
    assert_equal 0, subscription_item.reload.quantity

    expected_payload = {
      organization_id: organization_id,
      payment_type: "credit_card",
      product_key: "v0",
      product_type: "github.copilot",
      refund_amount_in_cents: 600,
      cancelled: true,
      refund_result: "Success"
    }

    assert_subset_hash expected_payload, events.first
    assert_equal last_performed_audit_entries, events
  end

  test "cancels the subscription item and instruments when the billing transaction is not refundable" do
    subscription_item = setup_subscription_item_and_transaction

    copilot_billing_transaction = Billing::BillingTransaction.for_user(@user).last
    T.must(copilot_billing_transaction).last_status = "failed"
    T.must(copilot_billing_transaction).save!

    events = perform_audit_entries(only: "billing.subscription_item_cancel_and_refund") do
      with_live_zuora("zuora/cancel_and_refund_copilot_for_individual") do
        GitHub.zuorest_client.class.any_instance.expects(:create_refund).never

        result = ::Billing::CancelAndRefundSubscriptionItemJob.perform_now(subscription_item)
        refute result.success?

        # subscription has been cancelled
        assert_equal 0, subscription_item.reload.quantity
      end
    end

    # subscription has been cancelled
    assert_equal 0, subscription_item.reload.quantity

    expected_payload = {
      payment_type: "credit_card",
      product_key: "v0",
      product_type: "github.copilot",
      refund_amount_in_cents: T.must(copilot_billing_transaction).amount_in_cents,
      cancelled: true,
      user_id: @user.id,
      refund_result: "Error : Billing transaction is not refundable, skipping"
    }

    assert_subset_hash expected_payload, events.first
    assert_equal last_performed_audit_entries, events
  end

  test "cancels the subscription item and retries the refund method only when a retryable error is raised" do
    subscription_item = setup_subscription_item_and_transaction
    # ensure most recent transaction to copilot contains the full amount
    copilot_billing_transaction = Billing::BillingTransaction.for_user(@user).last
    assert_equal 1000, T.must(copilot_billing_transaction).amount_in_cents

    organization_id = 12345

    # Raise an error on the first Zuora API call in the refund method
    Billing::Zuora::Invoice.expects(:invoices_for_transaction).times(3).raises(Errno::ETIMEDOUT)
    ::Billing::CancelAndRefundSubscriptionItemJob.any_instance.expects(:sleep).times(2)

    events = perform_audit_entries(only: "billing.subscription_item_cancel_and_refund") do
      with_live_zuora("zuora/cancel_and_refund_copilot_for_individual") do
        result = ::Billing::CancelAndRefundSubscriptionItemJob.perform_now(
          subscription_item,
          organization_id: organization_id,
        )
        result = T.must(result)
        assert result.failed?
      end
    end

    # subscription has been cancelled
    assert_equal 0, subscription_item.reload.quantity

    assert_equal 2, GitHub.dogstats.increments(
      "billing.cancel_and_refund_subscription_item_job.refund.retry",
      tags: ["error:Errno::ETIMEDOUT"]
    ).length

    expected_payload = {
      organization_id: organization_id,
      payment_type: "credit_card",
      product_key: "v0",
      product_type: "github.copilot",
      cancelled: true,
      user_id: @user.id,
      refund_result: "Error : Exhausted refund attempts",
    }

    assert_subset_hash expected_payload, events.first
    assert_equal last_performed_audit_entries, events
  end

  test "cancels the subscription item and instruments when the refund raises a non-retryable error" do
    subscription_item = setup_subscription_item_and_transaction
    # ensure most recent transaction to copilot contains the full amount
    copilot_billing_transaction = Billing::BillingTransaction.for_user(@user).last
    assert_equal 1000, T.must(copilot_billing_transaction).amount_in_cents

    organization_id = 12345
    GitHub.zuorest_client.class.any_instance.expects(:create_refund).raises(StandardError.new("boom"))

    events = perform_audit_entries(only: "billing.subscription_item_cancel_and_refund") do
      with_live_zuora("zuora/cancel_and_refund_copilot_for_individual") do
        result = ::Billing::CancelAndRefundSubscriptionItemJob.perform_now(
          subscription_item,
          organization_id: organization_id,
        )
        result = T.must(result)
        assert result.failed?
      end
    end

    # subscription has been cancelled
    assert_equal 0, subscription_item.reload.quantity

    expected_payload = {
      organization_id: organization_id,
      payment_type: "credit_card",
      product_key: "v0",
      product_type: "github.copilot",
      refund_amount_in_cents: T.must(copilot_billing_transaction).amount_in_cents,
      cancelled: true,
      user_id: @user.id,
      refund_result: "Error : boom"
    }

    assert_subset_hash expected_payload, events.first
    assert_equal last_performed_audit_entries, events
  end

  test "cancels the subscription item and instruments when the refund fails in Zuora" do
    subscription_item = setup_subscription_item_and_transaction
    # ensure most recent transaction to copilot contains the full amount
    copilot_billing_transaction = Billing::BillingTransaction.for_user(@user).last
    assert_equal 1000, T.must(copilot_billing_transaction).amount_in_cents

    organization_id = 12345
    GitHub.zuorest_client.class.any_instance.stubs(:create_refund).returns({ "success" => false })

    events = perform_audit_entries(only: "billing.subscription_item_cancel_and_refund") do
      with_live_zuora("zuora/cancel_and_refund_copilot_for_individual") do
        result = ::Billing::CancelAndRefundSubscriptionItemJob.perform_now(
          subscription_item,
          organization_id: organization_id,
        )
        result = T.must(result)
        assert result.failed?
      end
    end

    # subscription has been cancelled
    assert_equal 0, subscription_item.reload.quantity

    expected_payload = {
      organization_id: organization_id,
      payment_type: "credit_card",
      product_key: "v0",
      product_type: "github.copilot",
      refund_amount_in_cents: T.must(copilot_billing_transaction).amount_in_cents,
      cancelled: true,
      user_id: @user.id,
      refund_result: "Error : Cannot refund a transaction unless it is settled."
    }

    assert_subset_hash expected_payload, events.first
    assert_equal last_performed_audit_entries, events
  end

  test "cancels the subscription item and zeros out the invoice item in all open invoices" do
    subscription_item = setup_subscription_item_and_transaction
    organization_id = 12345

    events = perform_audit_entries(only: "billing.subscription_item_cancel_and_refund") do
      # VCR returns two open invoices, one with a $10 balance and another with a $5 balance
      with_live_zuora("zuora/cancel_and_refund_copilot_individual_with_open_invoices") do
        result = ::Billing::CancelAndRefundSubscriptionItemJob.perform_now(
          subscription_item,
          organization_id: organization_id,
        )
        result = T.must(result)
        assert result.success?, result.error_message
      end
    end

    # subscription has been cancelled
    assert_equal 0, subscription_item.reload.quantity

    expected_payload = {
      subscription_item_id: subscription_item.id,
      organization_id: organization_id,
      product_key: "v0",
      product_type: "github.copilot",
      zero_out_amount_in_cents: 1500,
      zero_out_result: "Success",
    }

    assert_subset_hash expected_payload, events.first
    assert_equal last_performed_audit_entries, events
  end

  test "cancels the subscription item and retries the job when an open invoice is in draft state" do
    subscription_item = setup_subscription_item_and_transaction

    GitHub.zuorest_client.class.any_instance.expects(:create_action).returns([
      {
        "Errors" => [{ "Code" => "INVALID_VALUE", "Message" => "Invoice Item Adjustments cannot be created for invoices with Draft status." }],
        "Success" => false
      },
      {
        "Errors" => [{ "Code" => "INVALID_VALUE", "Message" => "Invoice Item Adjustments cannot be created for invoices with Draft status." }],
        "Success" => false
      }
    ])

    events = perform_audit_entries(only: "billing.subscription_item_cancel_and_refund") do
      with_live_zuora("zuora/cancel_and_refund_copilot_individual_with_open_invoices") do
        assert_enqueued_with(job: ::Billing::CancelAndRefundSubscriptionItemJob) do
          ::Billing::CancelAndRefundSubscriptionItemJob.perform_now(subscription_item)
        end
      end
    end

    # subscription has been cancelled
    assert_equal 0, subscription_item.reload.quantity

    expected_payload = {
      subscription_item_id: subscription_item.id,
      product_key: "v0",
      product_type: "github.copilot",
      zero_out_amount_in_cents: 1500,
      zero_out_result: "Error : Invoice Item Adjustments cannot be created for invoices with Draft status.;" \
        "Invoice Item Adjustments cannot be created for invoices with Draft status.",
    }

    assert_subset_hash expected_payload, events.first
    assert_equal last_performed_audit_entries, events
  end

  test "cancels the subscription item and instruments when zeroing out raises an error" do
    subscription_item = setup_subscription_item_and_transaction
    organization_id = 12345

    GitHub.zuorest_client.class.any_instance.expects(:create_action).raises(StandardError.new("boom"))

    events = perform_audit_entries(only: "billing.subscription_item_cancel_and_refund") do
      with_live_zuora("zuora/cancel_and_refund_copilot_individual_with_open_invoices") do
        result = ::Billing::CancelAndRefundSubscriptionItemJob.perform_now(
          subscription_item,
          organization_id: organization_id,
        )
        result = T.must(result)
        assert result.failed?
      end
    end

    # subscription has been cancelled
    assert_equal 0, subscription_item.reload.quantity

    expected_payload = {
      subscription_item_id: subscription_item.id,
      organization_id: organization_id,
      product_key: "v0",
      product_type: "github.copilot",
      user_id: @user.id,
      zero_out_amount_in_cents: 1500,
      zero_out_result: "Error : boom"
    }

    assert_subset_hash expected_payload, events.first
    assert_equal last_performed_audit_entries, events
  end

  test "cancels the trial subscription item without attempting a refund and instruments" do
    subscription_item = setup_subscription_item_and_transaction(free_trial: true)
    organization_id = 12345

    Billing::PlanSubscription::Synchronizer.expects(:preview).never

    events = perform_audit_entries(only: "billing.subscription_item_cancel_and_refund") do
      with_live_zuora("zuora/cancel_and_refund_copilot_for_individual") do
        result = ::Billing::CancelAndRefundSubscriptionItemJob.perform_now(
          subscription_item,
          organization_id: organization_id
        )
        assert result.success?
      end
    end

    # subscription has been cancelled
    assert_equal 0, subscription_item.reload.quantity

    expected_payload = {
      subscription_item_id: subscription_item.id,
      organization_id: organization_id,
      product_key: "v0",
      product_type: "github.copilot",
      user_id: @user.id,
      trial_user: true
    }

    assert_subset_hash expected_payload, events.first
    assert_equal last_performed_audit_entries, events
  end

  context "when the subscription item is an in-app purchase" do
    test "cancels without attempting a refund and instruments when allow_cancelling_iap is set to true" do
      subscription_item = setup_subscription_item_and_transaction(in_app_purchase: true)
      organization_id = 12345

      events = perform_audit_entries(only: "billing.subscription_item_cancel_and_refund") do
        with_live_zuora("zuora/cancel_and_refund_copilot_for_individual") do
          result = ::Billing::CancelAndRefundSubscriptionItemJob.perform_now(
            subscription_item,
            organization_id: organization_id,
            allow_cancelling_iap: true
          )
          assert result.success?
        end
      end

      # subscription has been cancelled
      assert_equal 0, subscription_item.reload.quantity

      expected_payload = {
        subscription_item_id: subscription_item.id,
        organization_id: organization_id,
        product_key: "v0",
        product_type: "github.copilot",
        user_id: @user.id,
        iap_cancellation: true
      }

      assert_subset_hash expected_payload, events.first
      assert_equal last_performed_audit_entries, events
    end

    test "raises error if allow_cancelling_iap not set" do
      subscription_item = setup_subscription_item_and_transaction(in_app_purchase: true)
      organization_id = 12345

      expected_keys = {
        "exception.type" => "Billing::CancelAndRefundSubscriptionItemJob::InAppPurchaseCancellationError",
        "code.namespace" => "Billing::CancelAndRefundSubscriptionItemJob",
        "gh.billing.subscription_item.id" => subscription_item.id,
        "gh.billing.plan_subscription.id" => subscription_item.plan_subscription.id,
      }
      assert_logged(**expected_keys) do
        with_live_zuora("zuora/cancel_and_refund_copilot_for_individual") do
          result = ::Billing::CancelAndRefundSubscriptionItemJob.perform_now(
            subscription_item,
            organization_id: organization_id,
          )
          refute result.success?
        end
      end

      # subscription has not been cancelled
      assert_equal 1, subscription_item.reload.quantity
    end
  end

  test "reports to failbot, datadog, and splunk when job fails" do
    subscription_item = setup_subscription_item_and_transaction

    Billing::PlanSubscription::Synchronizer.stubs(:update).raises(
      StandardError.new("Something went wrong")
    )

    with_live_zuora("zuora/cancel_and_refund_copilot_for_individual") do
      expected_keys = {
        "exception.type" => "StandardError",
        "code.namespace" => "Billing::CancelAndRefundSubscriptionItemJob",
        "gh.billing.subscription_item.id" => subscription_item.id,
        "gh.billing.plan_subscription.id" => subscription_item.plan_subscription.id,
      }
      assert_logged(**expected_keys) do
        ::Billing::CancelAndRefundSubscriptionItemJob.perform_now(subscription_item)
      end
    end

    report = Failbot.reports.last
    assert_equal "Billing::CancelAndRefundSubscriptionItemJob", report["gh.job.name"]

    assert_equal 1, GitHub.dogstats.increments(
      "billing.cancel_and_refund_subscription_item_job.failed",
      tags: ["error:StandardError"]
    ).length
  end

  context "Zuorest::TooManyRequestsError" do
    test "it retries the job if 'Zuorest::TooManyRequestsError' is raised" do
      subscription_item = setup_subscription_item_and_transaction
      with_live_zuora("zuora/cancel_and_refund_copilot_for_individual") do
        Billing::PlanSubscription::Synchronizer.stubs(:update).raises(
          Zuorest::TooManyRequestsError.new("", {}, { "RateLimit-Reset" => "600" })
        )

        freeze_time do
          assert_enqueued_with(job: ::Billing::CancelAndRefundSubscriptionItemJob, at: Time.now + 600) do
            ::Billing::CancelAndRefundSubscriptionItemJob.perform_now(subscription_item)
          end
        end
      end
    end

    test "it retries 7 times for 'Zuorest::TooManyRequestsError' error" do
      subscription_item = setup_subscription_item_and_transaction

      with_live_zuora("zuora/cancel_and_refund_copilot_for_individual") do
        ::Billing::CancelAndRefundSubscriptionItemJob.any_instance.stubs(:exception_executions).returns(
          { "[Zuorest::TooManyRequestsError]" => 6 }
        )
        Billing::PlanSubscription::Synchronizer.stubs(:cancel).raises(
          Zuorest::TooManyRequestsError.new("", {}, { "RateLimit-Reset" => "600" })
        )

        assert_no_enqueued_jobs(only: ::Billing::CancelAndRefundSubscriptionItemJob) do
          ::Billing::CancelAndRefundSubscriptionItemJob.perform_now(subscription_item)
        end
      end
    end
  end
end
