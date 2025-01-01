# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::PaymentProcessors::ZuoraProcessorTest < GitHub::BillingTestCase
  include GitHub::ZuoraTestHelper

  def payment_processor(user)
    Billing::PaymentProcessors::ZuoraProcessor.new(
      user.customer.zuora_account_id,
      gateway: ::Billing::Zuora::PaymentGateway.new(user),
    )
  end

  fixtures do
    @user = create(:user)
    @customer_account = create(:customer_account, :zuora)
    @customer = @customer_account.customer
    @customer_user = @customer_account.user
  end

  # PayPal nonces are manually created and fetched through github.localhost
  # since Zuora doesn't allow test nonces from Braintree
  context "#update_payment_details" do
    test "updates to Stripe v2 if the feature flag is enabled" do
      with_live_zuora("zuora/payment_processors/successful_stripe_v2_credit_card_update_payment_details") do
        enable_feature_flag(:zuora_subscriptions_global, @user)

        assert zuora_successful_customer_account_creation(@user).success?
        customer = @user.reload.customer

        enable_feature_flag(:stripe_pay_in, @user)

        processor = payment_processor(@user)

        stripe_zuora_payment_method_id = "2c92c0f87801c54601780bf94dbe5951"
        payment_details = Billing::PaymentProcessorPaymentDetails.new(
          zuora_payment_method_id: stripe_zuora_payment_method_id,
          token: customer.payment_method.payment_token,
          has_card_on_file: true,
          country_code_alpha3: "USA",
          region: "New York",
          postal_code: "10000",
        )
        result = processor.update_payment_details(payment_details)

        assert result.success?
        assert record = result.record

        assert record.masked_number.present?
        assert record.expiration_month.present?
        assert record.expiration_year.present?
        assert record.card_type.present?
        assert record.postal_code.present?
        assert record.region.present?
        assert record.country_code_alpha3.present?
        assert record.unique_number_identifier.present?
        assert_nil record.paypal_email
        assert_equal stripe_zuora_payment_method_id, record.token
      end
    end

    test "works updating to paypal when user doesn't have a Braintree customer record" do
      with_live_zuora("zuora/payment_processors/successful_paypal_switch_without_braintree_customer") do
        assert zuora_successful_customer_account_creation(@user).success?
        customer = @user.reload.customer

        Braintree::Customer.find(customer.zuora_account_id).delete

        processor = payment_processor(@user)
        payment_details = Billing::PaymentProcessorPaymentDetails.new(
          login: @user.login,
          token: customer.payment_method.payment_token,
          has_card_on_file: true,
          paypal_nonce: "a9108cb0-4ed7-0a58-0e1f-4f8231b13b47",
          country_code_alpha3: "USA",
          region: "New York",
          postal_code: "10000",
        )
        result = processor.update_payment_details(payment_details)

        assert result.success?
        assert record = result.record

        assert_nil record.masked_number
        assert_nil record.expiration_month
        assert_nil record.expiration_year
        assert_nil record.card_type
        assert record.postal_code.present?
        assert record.region.present?
        assert record.country_code_alpha3.present?
        assert record.paypal_email.present?
        assert record.token.present?
      end
    end

    test "fails to update the payment method when a province is required and not provided" do
      with_live_zuora("zuora/payment_processors/failure_update_payment_details_without_required_province") do
        service = zuora_successful_customer_account_creation(@user)
        assert service.success?
        customer = @user.reload.customer

        processor = payment_processor(@user)
        payment_details = Billing::PaymentProcessorPaymentDetails.new(
          login: @user.login,
          token: customer.payment_method.payment_token,
          has_card_on_file: true,
          paypal_nonce: "8cd09147-b3d9-03c9-0ed8-e4a48ef4cd9d",
          country_code_alpha3: "CAN",
          region: "",
          postal_code: "KOH 1T0",
        )
        result = processor.update_payment_details(payment_details)

        refute result.success?
      end
    end

    test "updates from credit card to paypal successfully" do
      with_live_zuora("zuora/payment_processors/successful_credit_card_to_paypal_update_payment_details") do
        service = zuora_successful_customer_account_creation(@user)
        assert service.success?
        customer = @user.reload.customer

        processor = payment_processor(@user)

        payment_details = Billing::PaymentProcessorPaymentDetails.new(
          login: @user.login,
          token: customer.payment_method.payment_token,
          has_card_on_file: true,
          paypal_nonce: "9e9402b5-045d-086a-01aa-1a97415c2178",
          country_code_alpha3: "USA",
          region: "New York",
          postal_code: "10000",
        )
        result = processor.update_payment_details(payment_details)

        assert result.success?
        assert record = result.record

        assert_nil record.masked_number
        assert_nil record.expiration_month
        assert_nil record.expiration_year
        assert_nil record.card_type
        assert record.postal_code.present?
        assert record.region.present?
        assert record.country_code_alpha3.present?
        assert record.paypal_email.present?
        assert record.token.present?
      end
    end

    test "updates the default payment method for the customer ID" do
      with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
        service = zuora_successful_customer_account_creation(@user)
        assert service.success?
        customer = @user.reload.customer

        processor = payment_processor(@user)
        payment_details = Billing::PaymentProcessorPaymentDetails.new(
          zuora_payment_method_id: zuora_new_payment_method_id,
          token: customer.payment_method.payment_token,
          has_card_on_file: true,
          country_code_alpha3: "USA",
          region: "New York",
          postal_code: "10000",
        )
        result = processor.update_payment_details(payment_details)

        assert result.success?
        assert record = result.record

        assert record.masked_number.present?
        assert record.expiration_month.present?
        assert record.expiration_year.present?
        assert record.card_type.present?
        assert record.postal_code.present?
        assert record.region.present?
        assert record.country_code_alpha3.present?
        assert record.unique_number_identifier.present?
        assert_nil record.paypal_email
        assert_equal zuora_new_payment_method_id, record.token
      end
    end

    test "updates the SoldTo and BillTo contact information" do
      with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
        zuora_successful_customer_account_creation(@user)
        customer = @user.reload.customer

        processor = payment_processor(@user)
        payment_details = Billing::PaymentProcessorPaymentDetails.new(
          zuora_payment_method_id: zuora_new_payment_method_id,
          token: customer.payment_method.payment_token,
          has_card_on_file: true,
          country_code_alpha3: "USA",
          region: "New York",
          postal_code: "10000",
        )

        GitHub.zuorest_client.stubs(:update_action).returns([{ "Success" => true }])

        GitHub.zuorest_client.expects(:update_action).with(all_of(
          has_entry(type: "Contact"),
          has_entry(objects: anything),
        )).returns([{ "Success" => true }, { "Success" => true }])

        result = processor.update_payment_details(payment_details)

        assert result.success?
        assert record = result.record

        assert_equal payment_details.postal_code, record.postal_code
        assert_equal payment_details.region, record.region
        assert_equal payment_details.country_code_alpha3, record.country_code_alpha3
      end
    end
  end

  context "#clear_payment_details" do
    test "false when customer id is not present" do
      @customer.update!(zuora_account_id: nil, zuora_account_number: nil)
      processor = payment_processor(@customer_user)

      refute processor.clear_payment_details
    end

    test "true when job to remove payment methods is performed" do
      with_live_zuora("zuora/find_and_delete_cards_from_account") do
        @customer.update!(zuora_account_id: "2c92c0f95d59764d015d7be3e51402e5")
        processor = payment_processor(@customer_user)

        payment_methods = Zuorest::Model::PaymentMethod.find_by_account_id(processor.customer_id)
        refute_empty payment_methods

        assert processor.clear_payment_details

        payment_methods = Zuorest::Model::PaymentMethod.find_by_account_id(processor.customer_id)
        assert_empty payment_methods
      end
    end
  end
end
