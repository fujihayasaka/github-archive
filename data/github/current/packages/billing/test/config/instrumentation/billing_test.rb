# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingSubscribersTest < GitHub::TestCase
  fixtures do
    @user = create(:no_credit_card_user)
    @organization = create(:no_credit_card_org, :with_corporate_terms)
    @business = create(:business, :with_self_serve_payment)
  end

  context "billing.contact_create" do
    test "enqueues UpdateCustomerInStripeJob when a contact is created" do
      [@user, @organization, @business].each do |account|
        customer = account.customer
        refute customer.billing_contact.persisted?

        if account.feature_enabled?(:billing_update_customer_in_stripe)
          assert_enqueued_with(job: Billing::UpdateCustomerInStripeJob, args: [customer.id]) do
            create(:billing_contact, customer: customer)
          end
        else
          assert_no_enqueued_jobs(only: Billing::UpdateCustomerInStripeJob) do
            create(:billing_contact, customer: customer)
          end
        end

        assert customer.reload.billing_contact.persisted?
      end
    end
  end

  context "billing.contact_update" do
    test "enqueues UpdateCustomerInStripeJob when a contact is updated" do
      [@user, @organization, @business].each do |account|
        customer = account.customer
        contact = create(:billing_contact, customer: customer)
        new_address = "Mona Lisa St"

        if account.feature_enabled?(:billing_update_customer_in_stripe)
          assert_enqueued_with(job: Billing::UpdateCustomerInStripeJob, args: [customer.id]) do
            contact.update!(address1: new_address)
          end
        else
          assert_no_enqueued_jobs(only: Billing::UpdateCustomerInStripeJob) do
            contact.update!(address1: new_address)
          end
        end

        assert_equal new_address, contact.reload.address1
      end
    end
  end

  context "payment_method.create" do
    test "enqueues UpdatePaymentMethodInStripeJob when a credit card payment method is created" do
      [@user, @organization, @business].each do |account|
        customer = account.customer
        customer.payment_method&.destroy
        assert_nil customer.reload.payment_method

        if account.feature_enabled?(:billing_update_payment_method_in_stripe)
          assert_enqueued_with(job: Billing::UpdatePaymentMethodInStripeJob) do
            payment_method = create(:payment_method, customer: customer)
            payment_method.instrument_create(User.ghost)
          end
        else
          assert_no_enqueued_jobs(only: Billing::UpdatePaymentMethodInStripeJob) do
            payment_method = create(:payment_method, customer: customer)
            payment_method.instrument_create(User.ghost)
          end
        end

        payment_method = customer.reload.payment_method
        assert payment_method.present?
        assert payment_method.credit_card?
      end
    end

    test "does not enqueue UpdatePaymentMethodInStripeJob when a paypal payment method is created" do
      [@user, @organization, @business].each do |account|
        customer = account.customer
        customer.payment_method&.destroy
        assert_nil customer.reload.payment_method

        assert_no_enqueued_jobs(only: Billing::UpdatePaymentMethodInStripeJob) do
          create(:paypal_payment_method, customer: customer)
        end

        payment_method = customer.reload.payment_method
        assert payment_method.present?
        assert payment_method.paypal?
      end
    end
  end

  context "payment_method.update" do
    test "enqueues UpdatePaymentMethodInStripeJob when a credit card payment method is updated" do
      [@user, @organization, @business].each do |account|
        customer = account.customer
        customer.payment_method&.destroy
        payment_method = create(:payment_method, customer: customer)

        if account.feature_enabled?(:billing_update_payment_method_in_stripe)
          assert_enqueued_with(job: Billing::UpdatePaymentMethodInStripeJob, args: [payment_method.id]) do
            payment_method.instrument_update(User.ghost)
          end
        else
          assert_no_enqueued_jobs(only: Billing::UpdatePaymentMethodInStripeJob) do
            payment_method.instrument_update(User.ghost)
          end
        end
      end
    end

    test "does not enqueue UpdatePaymentMethodInStripeJob when a paypal payment method is updated" do
      [@user, @organization, @business].each do |account|
        customer = account.customer
        customer.payment_method&.destroy
        payment_method = create(:paypal_payment_method, customer: customer)

        assert_no_enqueued_jobs(only: Billing::UpdatePaymentMethodInStripeJob) do
          payment_method.instrument_update(User.ghost)
        end
      end
    end
  end
end if GitHub.billing_enabled?
