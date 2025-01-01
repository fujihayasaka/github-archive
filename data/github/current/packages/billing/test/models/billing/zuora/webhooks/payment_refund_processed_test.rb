# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::Webhooks::PaymentRefundProcessedTest < GitHub::BillingTestCase
  include GitHub::ZuoraTestHelper

  setup do
    ActionMailer::Base.deliveries.clear
  end

  context "#perform" do
    test "creates refund transaction based on the sales transaction" do
      with_live_zuora("zuora/payment_refund_processed") do
        zuora_refund_id = "2c92c0f962943fe1016296b6a01002e9"
        zuora_payment_id = "2c92c0fa624bb1f20162694a4ebe37bf"
        transaction_id = "75pkzfxe"
        transaction = create :billing_transaction, :zuora,
          platform_transaction_id: zuora_payment_id
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        zuora_webhook = build(
          :zuora_webhook,
          :payment_refund_processed,
          payload: { "RefundId" => zuora_refund_id, "PaymentId" => zuora_payment_id },
        )

        assert_difference "Billing::BillingTransaction.count", 1 do
          Billing::Zuora::Webhooks::PaymentRefundProcessed.perform(zuora_webhook)
        end

        refund_transaction = transaction.reload.refund
        assert refund_transaction
        assert_equal -5_00, refund_transaction.amount_in_cents
        assert_equal transaction_id, refund_transaction.transaction_id
        assert_equal transaction.plan_name, refund_transaction.old_plan_name
        assert_equal zuora_refund_id, refund_transaction.platform_transaction_id
        assert_equal transaction, refund_transaction.sale
        assert refund_transaction.settled?
        assert_equal 1, stats.increments("billing.refund").count
      end
    end

    test "doesn't create duplicate refund transactions" do
      with_live_zuora("zuora/payment_refund_processed") do
        zuora_refund_id = "2c92c0f962943fe1016296b6a01002e9"
        zuora_payment_id = "2c92c0fa624bb1f20162694a4ebe37bf"
        transaction_id = "75pkzfxe"
        transaction = create :billing_transaction, :zuora,
          platform_transaction_id: zuora_refund_id,
          transaction_id: transaction_id

        zuora_webhook = build(
          :zuora_webhook,
          :payment_refund_processed,
          payload: { "RefundId" => zuora_refund_id, "PaymentId" => zuora_payment_id },
        )

        assert_no_difference "Billing::BillingTransaction.count" do
          Billing::Zuora::Webhooks::PaymentRefundProcessed.perform(zuora_webhook)
        end
      end
    end

    test "sends email to the user after processing refund" do
      with_live_zuora("zuora/payment_refund_processed") do
        zuora_refund_id = "2c92c0f962943fe1016296b6a01002e9"
        zuora_payment_id = "2c92c0fa624bb1f20162694a4ebe37bf"
        transaction = create :billing_transaction, :zuora, platform_transaction_id: zuora_payment_id

        zuora_webhook = build(
          :zuora_webhook,
          :payment_refund_processed,
          payload: { "RefundId" => zuora_refund_id, "PaymentId" => zuora_payment_id },
        )

        Billing::Zuora::Webhooks::PaymentRefundProcessed.perform(zuora_webhook)

        assert_equal 1, ActionMailer::Base.deliveries.size
        email = ActionMailer::Base.deliveries.first
        assert_includes email.to, transaction.live_user&.email
      end
    end

    test "doesn't raise an error if the payment wasn't found" do
      zuora_refund_id = "2c92c0f962943fe1016296b6a01002e9"
      zuora_payment_id = "2c92c0f962943"

      zuora_webhook = build(
        :zuora_webhook,
        :payment_refund_processed,
        payload: { "RefundId" => zuora_refund_id, "PaymentId" => zuora_payment_id },
      )

      # The implicit assertion here is that it is not raising an ActiveRecord::NotFound
      Billing::Zuora::Webhooks::PaymentRefundProcessed.perform(zuora_webhook)
    end

    test "reverses transfers to stripe connect accounts when feature disabled" do
      listing = create(:sponsors_listing, :approved, :with_tier, :with_stripe_account)
      tier = listing.default_tier

      zuora_payment_id = "2c92c0f962943"
      billing_transaction = create \
        :billing_transaction,
        platform_transaction_id: zuora_payment_id,
        amount_in_cents: 500_00
      billing_transaction.user.disable_feature(:billing_refund_side_effects)
      create :billing_transaction_line_item, :sponsors,
        billing_transaction: billing_transaction,
        subscribable: tier

      zuora_webhook = build(
        :zuora_webhook,
        :payment_refund_processed,
        payload: { "RefundId" => "2c92c0f9629432c92c0f962943", "PaymentId" => zuora_payment_id },
      )

      ::Billing::Stripe::SaleTransfersReversal.expects(:perform).with do |args|
        assert_equal zuora_payment_id, args[:sale_transaction_id]
        refute_nil args[:stripe_refund_id]
        assert_equal "2c92c0f9629432c92c0f962943", args[:zuora_refund_id]
      end

      assert_enqueued_jobs 0, only: SponsorsProcessRefundJob do
        Billing::Zuora::Webhooks::PaymentRefundProcessed.perform(zuora_webhook)
      end
    end

    test "enqueues job to handle sponsorship refund when feature enabled" do
      listing = create(:sponsors_listing, :approved, :with_tier, :with_stripe_account)
      tier = listing.default_tier

      zuora_payment_id = "2c92c0f962943"
      billing_transaction = create \
        :billing_transaction,
        platform_transaction_id: zuora_payment_id,
        amount_in_cents: 500_00
      billing_transaction.user.enable_feature(:billing_refund_side_effects)
      create :billing_transaction_line_item, :sponsors,
        billing_transaction: billing_transaction,
        subscribable: tier

      zuora_webhook = build(
        :zuora_webhook,
        :payment_refund_processed,
        payload: { "RefundId" => "2c92c0f9629432c92c0f962943", "PaymentId" => zuora_payment_id },
      )

      assert_enqueued_jobs 1, only: SponsorsProcessRefundJob do
        Billing::Zuora::Webhooks::PaymentRefundProcessed.perform(zuora_webhook)
      end
    end

    test "does not reverse transfer if none of the sponsorships have a connect account" do
      no_connect_sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)

      zuora_payment_id = "2c92c0f962943"
      create(:billing_transaction, platform_transaction_id: zuora_payment_id)
      create(:billing_transaction_line_item, subscribable: no_connect_sponsors_tier, listing: no_connect_sponsors_tier.sponsors_listing)

      zuora_webhook = build(
        :zuora_webhook,
        :payment_refund_processed,
        payload: { "RefundId" => "2c92c0f9629432c92c0f962943", "PaymentId" => zuora_payment_id },
      )

      ::Billing::Stripe::SaleTransfersReversal.expects(:perform).never

      Billing::Zuora::Webhooks::PaymentRefundProcessed.perform(zuora_webhook)
    end

    test "does not reverse transfers for a partial refund with sponsorships" do
      listing = create(:sponsors_listing, :approved, :with_tier, :with_stripe_account)
      tier = listing.default_tier

      with_live_zuora("zuora/payment_refund_processed") do
        # 5_00 partial refund on 20_00 transaction
        zuora_refund_id = "2c92c0f962943fe1016296b6a01002e9"
        zuora_payment_id = "2c92c0fa624bb1f20162694a4ebe37bf"
        billing_transaction = create \
          :billing_transaction,
          :zuora,
          amount_in_cents: 20_00,
          platform_transaction_id: zuora_payment_id
        create :billing_transaction_line_item, :sponsors,
          billing_transaction: billing_transaction,
          subscribable: tier

        zuora_webhook = build(
          :zuora_webhook,
          :payment_refund_processed,
          payload: { "RefundId" => zuora_refund_id, "PaymentId" => zuora_payment_id },
        )

        ::Billing::Stripe::SaleTransfersReversal.expects(:perform).never

        assert_difference(-> { ::Billing::BillingTransaction.count }, 1) do
          Billing::Zuora::Webhooks::PaymentRefundProcessed.perform(zuora_webhook)
        end
      end
    end
  end

  def create_invoice_to_refund
    create_params = {
      accountKey: "8ad09fc2836a4ca101836bb79cac7e9e",
      termType: "EVERGREEN",
      contractEffectiveDate: GitHub::Billing.today.to_s,
      subscribeToRatePlans: [
        { productRatePlanId: "2c92c0f96f7e7c64016f81f342172952" },
      ],
      collect: true,
      runBilling: true
    }
    GitHub.zuorest_client.create_subscription(
      create_params,
      ::Billing::PlanSubscription::ZuoraSynchronizer::ZUORA_VERSION_HEADER
    )
  end
end if GitHub.billing_enabled?
