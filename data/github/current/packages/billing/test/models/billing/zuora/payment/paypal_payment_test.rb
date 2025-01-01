# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::Payment::PaypalPaymentTest < GitHub::BillingTestCase
  include GitHub::ZuoraTestHelper

  def paypal_payment(
    gateway_state: "Settled"
  )
    zuorest_payment = Zuorest::Model::Payment.new(
      "Gateway" => "Paypal",
      "GatewayState" => gateway_state,
    )
    zuora_payment = Billing::Zuora::Payment.new(zuorest_payment)
    Billing::Zuora::Payment::PaypalPayment.new(zuora_payment)
  end

  context "#transaction_status" do
    test "returns settled for a settled gateway state" do
      assert_equal Billing::BillingTransactionStatuses::ALL[:settled], paypal_payment.transaction_status
    end

    test "returns submitted for settling for a submitted gateway state" do
      assert_equal Billing::BillingTransactionStatuses::ALL[:submitted_for_settlement],
        paypal_payment(gateway_state: "Submitted").transaction_status
    end

    test "returns processor declined for not submitted gateway state" do
      assert_equal Billing::BillingTransactionStatuses::ALL[:processor_declined],
        paypal_payment(gateway_state: "NotSubmitted").transaction_status
    end

    test "returns processor declined for failed to settle gateway state" do
      assert_equal Billing::BillingTransactionStatuses::ALL[:processor_declined],
        paypal_payment(gateway_state: "FailedToSettle").transaction_status
    end
  end
end
