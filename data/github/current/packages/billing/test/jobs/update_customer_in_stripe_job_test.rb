# typed: true
# frozen_string_literal: true

require "test_helper"

class UpdateCustomerInStripeJobTest < GitHub::TestCase
  include GitHub::LoggerHelper

  test "creates a new stripe customer for the provided dotcom customer" do
    user = create(:credit_card_user)
    customer = user.customer
    metadata = {
      dotcom_customer_id: customer.id,
      zuora_account_url: "#{GitHub.zuora_host}/apps/CustomerAccount.do?method=view&id=#{customer.zuora_account_id}"
    }

    ::Stripe::Customer.expects(:retrieve).never
    ::Stripe::Customer.expects(:create).once
      .with({ metadata: metadata }, { api_key: GitHub.stripe_v3_api_key })
      .returns(::Stripe::Customer.construct_from(id: "cus_123"))
    ::Stripe::Customer.expects(:update).never

    Billing::UpdateCustomerInStripeJob.perform_now(customer.id)
  end

  test "updates the existing stripe customer for the provided dotcom customer when there are new changes" do
    user = create(:credit_card_user, :with_valid_contact_for_billing)
    customer = user.customer
    contact = customer.billing_contact

    key = "stripe_customer_id_for_dotcom_customer_#{customer.id}"
    Billing::Kv.store.set(key, "cus_123")

    ::Stripe::Customer.expects(:retrieve).once
      .with("cus_123", { api_key: GitHub.stripe_v3_api_key })
      .returns(::Stripe::Customer.construct_from(id: "cus_123", address: nil, name: nil, shipping: nil, metadata: nil))
    ::Stripe::Customer.expects(:create).never

    address = {
      city: contact.city,
      country: contact.country_code,
      line1: contact.address1,
      postal_code: contact.postal_code,
      state: contact.region,
    }

    metadata = {
      dotcom_customer_id: customer.id,
      zuora_account_url: "#{GitHub.zuora_host}/apps/CustomerAccount.do?method=view&id=#{customer.zuora_account_id}"
    }

    ::Stripe::Customer.expects(:update).once
      .with("cus_123", { name: contact.fullname, address: address, metadata: metadata }, { api_key: GitHub.stripe_v3_api_key })
      .returns(::Stripe::Customer.construct_from(id: "cus_123"))

    Billing::UpdateCustomerInStripeJob.perform_now(customer.id)
  end

  test "does not update the existing stripe customer for the provided dotcom customer when there are no changes" do
    user = create(:credit_card_user)
    customer = user.customer

    key = "stripe_customer_id_for_dotcom_customer_#{customer.id}"
    Billing::Kv.store.set(key, "cus_123")

    metadata = {
      dotcom_customer_id: customer.id,
      zuora_account_url: "#{GitHub.zuora_host}/apps/CustomerAccount.do?method=view&id=#{customer.zuora_account_id}"
    }
    ::Stripe::Customer.expects(:retrieve).once
      .with("cus_123", { api_key: GitHub.stripe_v3_api_key })
      .returns(::Stripe::Customer.construct_from(id: "cus_123", address: nil, name: nil, shipping: nil, metadata: metadata))
    ::Stripe::Customer.expects(:create).never
    ::Stripe::Customer.expects(:update).never

    Billing::UpdateCustomerInStripeJob.perform_now(customer.id)
  end

  test "deletes the stripe customer id reference and recreates the stripe customer when the existing stripe customer does not exist" do
    user = create(:credit_card_user)
    customer = user.customer

    key = "stripe_customer_id_for_dotcom_customer_#{customer.id}"
    Billing::Kv.store.set(key, "cus_123")

    metadata = {
      dotcom_customer_id: customer.id,
      zuora_account_url: "#{GitHub.zuora_host}/apps/CustomerAccount.do?method=view&id=#{customer.zuora_account_id}"
    }

    ::Stripe::Customer.expects(:retrieve).once
      .with("cus_123", { api_key: GitHub.stripe_v3_api_key })
      .raises(::Stripe::InvalidRequestError.new("No such customer: 'cus_123'", {}))
    ::Stripe::Customer.expects(:create).once
      .with({ metadata: metadata }, { api_key: GitHub.stripe_v3_api_key })
      .returns(::Stripe::Customer.construct_from(id: "cus_123"))
    ::Stripe::Customer.expects(:update).never

    Billing::UpdateCustomerInStripeJob.perform_now(customer.id)
  end

  test "deletes the stripe customer id reference and recreates the stripe customer when the existing stripe customer has been deleted" do
    user = create(:credit_card_user)
    customer = user.customer

    key = "stripe_customer_id_for_dotcom_customer_#{customer.id}"
    Billing::Kv.store.set(key, "cus_123")

    metadata = {
      dotcom_customer_id: customer.id,
      zuora_account_url: "#{GitHub.zuora_host}/apps/CustomerAccount.do?method=view&id=#{customer.zuora_account_id}"
    }

    ::Stripe::Customer.expects(:retrieve).once
      .with("cus_123", { api_key: GitHub.stripe_v3_api_key })
      .returns(::Stripe::Customer.construct_from(id: "cus_123", deleted: true))
    ::Stripe::Customer.expects(:create).once
      .with({ metadata: metadata }, { api_key: GitHub.stripe_v3_api_key })
      .returns(::Stripe::Customer.construct_from(id: "cus_123"))
    ::Stripe::Customer.expects(:update).never

    Billing::UpdateCustomerInStripeJob.perform_now(customer.id)
  end
end
