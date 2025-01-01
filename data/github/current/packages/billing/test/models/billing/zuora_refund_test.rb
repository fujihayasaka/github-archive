# typed: strict
# frozen_string_literal: true

require "test_helper"

class ZuoraRefundTest < GitHub::BillingTestCase
  include GitHub::ZuoraTestHelper

  context "#process" do
    test "refunds the given amount and zeroes out the invoice when the user has been deleted" do
      with_live_zuora("zuora/successful_refund") do
        zuora_transaction_id = "2c92c0fa624bb1f20162694a4ebe37bf"
        braintree_transaction_id = "jqnpy0s3"
        invoice = T.must(Billing::Zuora::Invoice.invoices_for_transaction(zuora_transaction_id).first)

        transaction = create :billing_transaction, :zuora,
          transaction_id: braintree_transaction_id,
          platform_transaction_id: zuora_transaction_id,
          amount_in_cents: 7_00

        transaction.user.destroy
        transaction = Billing::BillingTransaction.find(transaction.id)

        response = assert_difference "Billing::BillingTransaction.count", 1 do
          Billing::ZuoraRefund.process transaction, Billing::Money.new(5_00)
        end

        assert response.success?
        assert transaction.refund

        zuora_payment = Zuorest::Model::Payment.find(zuora_transaction_id)
        assert_equal 5, zuora_payment["RefundAmount"]
        assert_equal -500, transaction.refund&.amount_in_cents
        assert_equal braintree_transaction_id, transaction.refund&.sale_transaction_id
        assert transaction.refund&.settled?

        invoice = Billing::Zuora::Invoice.new(invoice.invoice_id)
        assert_equal 0, invoice.balance
      end
    end

    test "refunds the given amount and zeros the invoice without logging the transaction" do
      with_live_zuora("zuora/successful_refund_processed_in_webhook") do
        response = create_invoice_to_refund
        amount_paid = Billing::Money.new(response["paidAmount"] * 100)
        payment_id = response["paymentId"]
        invoice_id = response["invoiceId"]
        transaction_id = "transaction-id"
        transaction = create(:billing_transaction, :zuora,
          transaction_id: transaction_id,
          platform_transaction_id: payment_id,
          amount_in_cents: amount_paid.cents,
        )

        assert_difference "Billing::BillingTransaction.count", 0 do
          result = Billing::ZuoraRefund.process transaction, amount_paid
          assert result.success?
        end

        # we rely on Zuora webhooks to generate the refund transaction
        refute transaction.refund

        zuora_payment = Zuorest::Model::Payment.find(payment_id)
        assert_equal amount_paid.dollars, zuora_payment["RefundAmount"]

        invoice = Billing::Zuora::Invoice.new(invoice_id)
        # See https://github.com/github/gitcoin/issues/9751, this should be 0 but due to
        # taxation in Sandbox we're seeing a small amount remaining.
        assert_equal invoice.tax_amount, invoice.balance
      end
    end

    test "returns error message for non-settled payments" do
      with_live_zuora("zuora/unsuccessful_refund") do
        zuora_transaction_id = "2c92c0f966a9b7400166c05ca0a87c86"
        braintree_transaction_id = "2rqs216w"
        transaction = create :billing_transaction, :zuora,
          transaction_id: braintree_transaction_id,
          platform_transaction_id: zuora_transaction_id,
          amount_in_cents: 28_00

        response = assert_no_difference "Billing::BillingTransaction.count" do
          Billing::ZuoraRefund.process transaction, Billing::Money.new(5_00)
        end

        refute response.success?
        refute transaction.refund
        assert_equal "Cannot refund a transaction unless it is settled.", response.error_message

        zuora_payment = Zuorest::Model::Payment.find(zuora_transaction_id)
        assert_equal 0, zuora_payment["RefundAmount"]
      end
    end

    test "returns error message when not found" do
      GitHub.zuorest_client.expects(:create_refund).raises(Zuorest::HttpError.new(404, ""))

      transaction = create :billing_transaction, :zuora

      response = assert_no_difference "Billing::BillingTransaction.count" do
        Billing::ZuoraRefund.process transaction, Billing::Money.new(5_00)
      end

      refute response.success?
      assert_equal "Error:: HTTP 404", response.error_message
    end

    test "doesn't zero out refund on timeout with no refund amount on transaction" do
      Billing::Zuora::Payment.expects(:find).returns(
        Billing::Zuora::Payment.new(Zuorest::Model::Payment.new("RefundAmount" => 0))
      )
      GitHub.zuorest_client.expects(:create_refund).raises(Faraday::TimeoutError.new)
      transaction = create :billing_transaction, :zuora

      Billing::Zuora::ZeroOutInvoices.expects(:for_transaction).never

      assert_raises Faraday::TimeoutError do
        Billing::ZuoraRefund.process transaction, Billing::Money.new(5_00)
      end
    end

    test "zeroes out refund on timeout if the refund was successful" do
      refund_amount_in_cents = 5_00

      Billing::Zuora::Payment.expects(:find).returns(
        Billing::Zuora::Payment.new(Zuorest::Model::Payment.new("RefundAmount" => 5))
      )
      GitHub.zuorest_client.expects(:create_refund).raises(Faraday::TimeoutError.new)
      transaction = create :billing_transaction, :zuora

      ::Billing::Zuora::ZeroOutInvoices
        .expects(:for_transaction)
        .with(transaction.platform_transaction_id)
        .returns(GitHub::Billing::Result.success)

      assert_raises Faraday::TimeoutError do
        Billing::ZuoraRefund.process transaction, Billing::Money.new(refund_amount_in_cents)
      end
    end

    test "refunds the given amount from the speficied invoice when a payment has multiple invoices" do
      with_live_zuora("zuora/successful_refund_multiple_invoices") do
        zuora_transaction_id = "8ad081c686bfcd410186c1b9e4df6dd1"
        stripe_charge_id = "ch_3MjOQVEQsq43iHhX0vKi4QAt"
        invoice_id = "8ad08d29865eb0940186604e4eec6860"

        zuora_payment = Zuorest::Model::Payment.find(zuora_transaction_id)
        assert_equal 0, zuora_payment["RefundAmount"]

        payment_invoices = Billing::Zuora::Invoice.invoices_for_transaction(zuora_transaction_id)
        assert_equal 2, payment_invoices.size

        invoice = GitHub.zuorest_client.get_object_invoice(invoice_id)
        assert_equal 0, invoice["RefundAmount"]

        amount_paid = Billing::Money.new(zuora_payment["Amount"] * 100)
        amount_to_be_refunded = Billing::Money.new(10_000) # $100.00

        transaction = create :billing_transaction, :zuora,
          transaction_id: stripe_charge_id,
          platform_transaction_id: zuora_transaction_id,
          amount_in_cents: amount_paid.cents

        # pass invoice_id => refund amount mapping since the payment has multiple invoices
        response = Billing::ZuoraRefund.process(transaction, amount_to_be_refunded, { invoice_id => amount_to_be_refunded })

        assert response.success?

        zuora_payment = Zuorest::Model::Payment.find(zuora_transaction_id)
        assert_equal amount_to_be_refunded.dollars, zuora_payment["RefundAmount"]

        invoice = ::Billing::Zuora::Invoice.new invoice_id
        assert_equal amount_to_be_refunded.dollars, invoice.refund_amount
        assert_equal 0, invoice.balance
      end
    end

  end

  sig { returns(T::Hash[T.any(Symbol, String), T.untyped]) }
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
end
