# typed: true
# frozen_string_literal: true

require "test_helper"

class UpdatePaymentMethodInStripeJobTest < GitHub::TestCase
  include GitHub::LoggerHelper

  test "attaches the stripe payment method to the existing stripe customer" do
    user = create(:credit_card_user)
    customer = user.customer
    payment_method = customer.payment_method

    query = "select responsestring from paymentmethodtransactionlog where paymentmethodid = '#{payment_method.payment_token}' limit 1"
    GitHub.zuorest_client.class.any_instance.expects(:query_action)
      .with(queryString: query)
      .returns({ "records" => [{ "ResponseString" => "[], [ResponseBody={\"payment_method\": \"pm_123\"}, ResponseCode=200]" }] })

    key = "stripe_customer_id_for_dotcom_customer_#{customer.id}"
    Billing::Kv.store.set(key, "cus_123")

    ::Stripe::PaymentMethod.expects(:retrieve).once
      .with("pm_123", { api_key: GitHub.stripe_v3_api_key })
      .returns(::Stripe::PaymentMethod.construct_from(id: "pm_123", customer: nil))

    ::Stripe::PaymentMethod.expects(:attach).once
      .with("pm_123", { customer: "cus_123" }, { api_key: GitHub.stripe_v3_api_key })
      .returns(::Stripe::PaymentMethod.construct_from(id: "pm_123", customer: "cus_123"))

    Billing::UpdatePaymentMethodInStripeJob.perform_now(payment_method.id)
  end

  test "attaches the stripe payment method to a new stripe customer" do
    user = create(:credit_card_user)
    customer = user.customer
    payment_method = customer.payment_method

    query = "select responsestring from paymentmethodtransactionlog where paymentmethodid = '#{payment_method.payment_token}' limit 1"
    GitHub.zuorest_client.class.any_instance.expects(:query_action)
      .with(queryString: query)
      .returns({ "records" => [{ "ResponseString" => "[], [ResponseBody={\"payment_method\": \"pm_123\"}, ResponseCode=200]" }] })

    ::Stripe::PaymentMethod.expects(:retrieve).once
      .with("pm_123", { api_key: GitHub.stripe_v3_api_key })
      .returns(::Stripe::PaymentMethod.construct_from(id: "pm_123", customer: nil))

    Billing::UpdateCustomerInStripeJob.any_instance.expects(:perform)
      .with(customer.id)
      .returns(::Stripe::Customer.construct_from(id: "cus_123"))

    ::Stripe::PaymentMethod.expects(:attach).once
      .with("pm_123", { customer: "cus_123" }, { api_key: GitHub.stripe_v3_api_key })
      .returns(::Stripe::PaymentMethod.construct_from(id: "pm_123", customer: "cus_123"))

    Billing::UpdatePaymentMethodInStripeJob.perform_now(payment_method.id)
  end

  test "does nothing if the payment method token has been cleared" do
    user = create(:credit_card_user)
    customer = user.customer
    payment_method = customer.payment_method
    payment_method.update!(payment_token: PaymentMethod::PAYMENT_TOKEN_CLEARED)

    GitHub.zuorest_client.class.any_instance.expects(:query_action).never
    ::Stripe::PaymentMethod.expects(:retrieve).never
    ::Stripe::PaymentMethod.expects(:attach).never

    Billing::UpdatePaymentMethodInStripeJob.perform_now(payment_method.id)
  end

  test "does nothing if we cannot retrieve the stripe payment method id" do
    user = create(:credit_card_user)
    customer = user.customer
    payment_method = customer.payment_method

    query = "select responsestring from paymentmethodtransactionlog where paymentmethodid = '#{payment_method.payment_token}' limit 1"
    GitHub.zuorest_client.class.any_instance.expects(:query_action)
      .with(queryString: query)
      .returns({ "records" => [] })

    ::Stripe::PaymentMethod.expects(:retrieve).never
    ::Stripe::PaymentMethod.expects(:attach).never

    Billing::UpdatePaymentMethodInStripeJob.perform_now(payment_method.id)
  end

  test "does nothing if we cannot retrieve the stripe payment method" do
    user = create(:credit_card_user)
    customer = user.customer
    payment_method = customer.payment_method

    query = "select responsestring from paymentmethodtransactionlog where paymentmethodid = '#{payment_method.payment_token}' limit 1"
    GitHub.zuorest_client.class.any_instance.expects(:query_action)
      .with(queryString: query)
      .returns({ "records" => [{ "ResponseString" => "[], [ResponseBody={\"payment_method\": \"pm_123\"}, ResponseCode=200]" }] })

    key = "stripe_customer_id_for_dotcom_customer_#{customer.id}"
    Billing::Kv.store.set(key, "cus_123")

    ::Stripe::PaymentMethod.expects(:retrieve).once
      .with("pm_123", { api_key: GitHub.stripe_v3_api_key })
      .raises(::Stripe::InvalidRequestError.new("No such payment method: 'pm_123'", {}))

    ::Stripe::PaymentMethod.expects(:attach).never

    Billing::UpdatePaymentMethodInStripeJob.perform_now(payment_method.id)
  end
end
