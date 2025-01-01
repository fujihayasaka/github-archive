# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::Webhooks::CreditBalanceUsedForInvoiceTest < GitHub::BillingTestCase
  include DogstatsTestHelpers
  include GitHub::ZuoraTestHelper

  setup do
    ActionMailer::Base.deliveries.clear
  end

  fixtures do
    # Both IDs come from the fixtures being used
    cba_id = "2c92c0f8748a8d3c01749388f597514a"
    zuora_account_id = "2c92c0fb743532a401744ae20ff065ab"

    @webhook = create(:zuora_webhook,
      :credit_balance_used_for_invoice,
      account_id: zuora_account_id,
      payload: {
        "CreditBalanceAdjustmentId" => cba_id,
        "InvoiceAmount" => "25",
        "InvoiceCreditBalanceAdjustmentAmount" => "-25",
      }
    )
    @subscription = create(:billing_plan_subscription,
      :zuora,
      zuora_subscription_id: "2c92c0f974915284017492f951df2aed",
      zuora_subscription_number: "A-S00086179"
    )
    @user = @subscription.user
    @user.customer.update!(zuora_account_id: zuora_account_id)
  end

  context "#perform" do
    test "does not process the paid invoice if the invoice is not fully covered by the credit balance" do
      @webhook.payload["InvoiceCreditBalanceAdjustmentAmount"] = "-20"

      Billing::Zuora::Webhooks::ProcessPaidInvoice.expects(:perform).never
      @webhook.perform

      assert_predicate @webhook, :ignored?
    end

    test "does not process the paid invoice for a deleted account" do
      @user.destroy
      @webhook.perform
      assert_predicate @webhook, :ignored?
    end

    test "does not process the paid invoice for a suspended account" do
      @user.suspend("Did something bad")
      @webhook.perform
      assert_predicate @webhook, :ignored?
    end

    test "does not process the paid invoice if there is no plan subscription for the webhook" do
      @subscription.destroy
      Billing::Zuora::Webhooks::ProcessPaidInvoice.expects(:perform).never
      @webhook.perform
      assert_predicate @webhook, :ignored?
    end

    test "does not process the paid invoice if there is already a transaction for the credit balance adjustment" do
      with_live_zuora("zuora/credit_balance_used_for_invoice_webhook") do
        assert_difference "@user.reload.billing_transactions.count", 1 do
          @webhook.perform
        end
      end

      Billing::ResetBillingStatus.expects(:perform).never
      Billing::PlanSubscription::CreateBillingTransaction.expects(:perform).never
      Billing::PlanSubscription::SendReceipt.expects(:perform).never

      with_live_zuora("zuora/credit_balance_used_for_invoice_webhook") do
        assert_difference("@user.reload.billing_transactions.count", 0) { @webhook.perform }
      end

      assert_predicate @webhook, :processed?
    end

    test "raises an error if the zuora subscription is not synched" do
      @subscription.update(zuora_subscription_number: nil)
      stubbed_sync_result = GitHub::Billing::Result.failure("Something went wrong")
      Billing::PlanSubscription.any_instance.expects(:synchronize_with_lock).returns(stubbed_sync_result)

      assert_raises "Zuora subscription not synched, cannot process payment" do
        @webhook.perform
      end

      assert_predicate @webhook, :pending?
    end

    test "creates a billing transaction for the invoice paid with the credit balance" do
      with_live_zuora("zuora/credit_balance_used_for_invoice_webhook") do
        assert_difference("@user.reload.billing_transactions.count", 1) { @webhook.perform }
      end

      assert_predicate @webhook, :processed?

      billing_transaction = @user.reload.billing_transactions.last
      assert_equal "CBA-00000146", billing_transaction.transaction_id
      assert_predicate billing_transaction, :credit_balance_adjustment_transaction?
    end

    test "transfers sponsorship payments for invoices paid by credit balance" do
      # need a sponsors-purpose subscription
      @subscription.update!(purpose: :sponsors)
      listing = create(:sponsors_listing, :approved, :with_tier, :with_stripe_account, name: "Adams, Hintz and Corwin")
      create(:sponsorship, sponsor: @user, tier: listing.default_tier)

      # Mock the billing transaction required for the sponsorship transfer
      billing_transaction = create(:billing_transaction, plan_subscription: @subscription)
      create(
        :billing_transaction_line_item,
        :sponsors,
        billing_transaction: billing_transaction,
        listing: listing,
        subscribable: listing.default_tier
      )
      ::Billing::PlanSubscription::CreateBillingTransaction.expects(:perform)
        .returns(billing_transaction.reload)

      ::Billing::Stripe::TransferPayments.expects(:perform)

      with_live_zuora("zuora/credit_balance_used_for_invoice_webhook") do
        @webhook.perform
      end

      assert_predicate @webhook, :processed?
    end

    # https://github.com/github/sponsors/issues/4617
    test "sets last_status for invoices paid by credit balance" do
      with_live_zuora("zuora/credit_balance_used_for_invoice_webhook") do
        assert_difference("@user.reload.billing_transactions.count", 1) { @webhook.perform }
      end

      assert_predicate @webhook, :processed?

      billing_transaction = @user.reload.billing_transactions.last
      assert_equal "credit_balance_adjusted", billing_transaction.last_status
    end

    test "updates zuora subscription ids when user subscription isn't found" do
      synchronize_github_products_to_zuora
      @subscription.update(zuora_subscription_number: nil)
      @user.update(plan: :pro, billed_on: GitHub::Billing.today + 1.month)
      zuora_successful_customer_account_creation(@user)
      @user.reload

      with_live_zuora("zuora/credit_balance_used_for_invoice_webhook_attach_subscription") do
        @user.customer.update!(bill_cycle_day: @user.billed_on.day, zuora_account_id: @webhook.account_id)

        assert_nil @user.plan_subscription.zuora_subscription_number

        assert_difference("Billing::BillingTransaction.count", 1) { @webhook.perform }

        @user.reload

        assert_dogstats_increment("billing.missing_zuora_subscription.count",
          tags: ["class:billing/zuora/webhooks/credit_balance_used_for_invoice"]
        )

        assert_predicate @webhook, :processed?

        billing_transaction = Billing::BillingTransaction.last
        assert_equal @subscription, T.must(billing_transaction).plan_subscription
        assert_equal @webhook.payload["CreditBalanceAdjustmentId"], T.must(billing_transaction).platform_transaction_id
        refute_nil @user.plan_subscription.zuora_subscription_number
      end
    end
  end
end
