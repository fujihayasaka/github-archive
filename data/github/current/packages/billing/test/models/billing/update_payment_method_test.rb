# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::UpdatePaymentMethodTest < GitHub::BillingTestCase
  include DogstatsTestHelpers
  include GitHub::BrainTree::TestHelper
  include GitHub::LoggerHelper
  include GitHub::ZuoraTestHelper

  setup do
    ActionMailer::Base.deliveries.clear
    # Calls to User.payment_amount need this otherwise we will attempt to reach out to the Meuse API
    Billing::Pricing.any_instance.stubs(:metered_usage_cost).returns(0)
  end

  def update_payment_method(target, payment_details, opts = nil)
    opts ||= {}
    skip_synchronization = opts.delete(:skip_synchronization) || false
    service = Billing::UpdatePaymentMethod.perform(target, payment_details.merge(opts), skip_synchronization: skip_synchronization)
    service.response
  end

  test "creates a payment method record when one doesn't exist" do
    with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
      user = create :user, billing_attempts: 0
      zuora_successful_customer_account_creation(user)
      user.reload
      user.payment_method.destroy
      user.reload

      refute user.payment_method

      result = update_payment_method(user, zuora_parsed_payment_details, skip_synchronization: true)

      assert result.success?
      user.reload
      assert user.payment_method
    end
  end

  test "creates successfully creates a PayPal payment method for a Business" do
    business = create :business, :with_credit_card
    zuora_successful_customer_account_creation(business)

    paypal_nonce = "4a70cbae-dbe2-0edf-02e8-63f52219ec2b"
    billing_address = { country_code_alpha3: "USA", region: "New York", postal_code: "10036" }

    # Stubbing given we already have tests for the paypal integration and the goal of this test is to verify
    # the businesses don't raise an error when #paypal_switch_error_message is run.
    Customer.any_instance.stubs(:update_payment_method_details).returns(GitHub::Billing::Result.success)

    result = update_payment_method(business,
        { actor: business.owners.first, paypal_nonce: paypal_nonce, billing_address: billing_address },
        skip_synchronization: true
      )

    assert result.success?
  end

  test "disallows changing to PayPal when user sponsor has an active sponsorship" do
    customer_account = create(:credit_card_customer_account, :zuora)
    user = customer_account.user
    user.emails.first.verify!
    create(:billing_plan_subscription, :zuora, user: user)
    create(:sponsorship, sponsor: user)
    create(:sponsorship, :one_time, sponsor: user) # should not be counted
    paypal_nonce = "4a70cbae-dbe2-0edf-02e8-63f52219ec2b"
    billing_address = { country_code_alpha3: "USA", region: "New York", postal_code: "10036" }

    Billing::ZuoraPaypal.expects(:create_payment_method).never

    result = update_payment_method(user, { paypal_nonce: paypal_nonce, billing_address: billing_address })

    refute_predicate result, :success?
    assert_equal "You must cancel your recurring sponsorship first before you can switch to PayPal.",
      result.error_message
  end if GitHub.sponsors_enabled?

  test "disallows changing to PayPal when org sponsor has active sponsorships" do
    org = create(:organization)
    create(:billing_plan_subscription, :zuora, user: org)
    create_pair(:sponsorship, sponsor: org)
    paypal_nonce = "4a70cbae-dbe2-0edf-02e8-63f52219ec2b"
    billing_address = { country_code_alpha3: "USA", region: "New York", postal_code: "10036" }

    Billing::ZuoraPaypal.expects(:create_payment_method).never

    result = update_payment_method(org, { paypal_nonce: paypal_nonce, billing_address: billing_address })

    refute_predicate result, :success?
    assert_equal "You must cancel @#{org}'s 2 recurring sponsorships first before you can switch to PayPal.",
      result.error_message
  end if GitHub.sponsors_enabled?

  test "prevents updating payment method if the user has been spam-flagged" do
    user = create(:credit_card_user)
    user.stubs(:spammy?).returns(true)
    response = update_payment_method(user, zuora_payment_method_id: zuora_new_payment_method_id)
    assert response.failed?
    assert_match /This account has been flagged. #{GitHub.support_link_text} for further information./, response.error_message
  end

  test "enqueues VerifyPaymentMethodJob after successfully updating a credit card" do
    with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
      user = create(:user)

      zuora_successful_customer_account_creation(user)
      user.reload

      assert_enqueued_jobs 1, only: Billing::VerifyPaymentMethodJob do
        result = update_payment_method(user, zuora_payment_method_id: zuora_new_payment_method_id)
        assert result.success?
        assert_nil result.error_message
      end

      user.reload
      assert user.has_credit_card?
      assert_equal zuora_new_payment_method_id, user.payment_method.payment_token
    end
  end

  test "successful response when updating a credit card" do
    with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
      user = create(:user)

      zuora_successful_customer_account_creation(user)
      user.reload

      assert_enqueued_jobs 1, only: Billing::VerifyPaymentMethodJob do
        result = update_payment_method(user, zuora_payment_method_id: zuora_new_payment_method_id)
        assert result.success?
        assert_nil result.error_message
      end

      user.reload
      assert user.has_credit_card?
      assert_equal zuora_new_payment_method_id, user.payment_method.payment_token
    end
  end

  test "failure response with an invalid payment method ID" do
    with_live_zuora("zuora/failure_credit_card_update_payment_details_with_invalid_payment_id") do
      user = create(:user)

      zuora_successful_customer_account_creation(user)
      user.reload

      previous_payment_token = user.payment_method.payment_token

      result = update_payment_method(
        user,
        zuora_payment_method_id: "2c92c0f962943",
        billing_address: {
          country_code_alpha3: "USA",
          region: "New York",
          postal_code: "10036",
        },
      )

      refute result.success?
      assert_nil result.record
      assert_equal "Payment method not found", result.error_message

      user.reload
      assert user.has_credit_card?
      assert_equal previous_payment_token, user.payment_method.payment_token
    end
  end

  test "logs the outstanding balance when updating a credit card" do
    with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
      user = create(:user)
      zuora_successful_customer_account_creation(user)
      user.reload
      user.plan_subscription.update(balance_in_cents: 2500)
      user.plan_subscription.cache_outstanding_balance
      user.plan_subscription.update(balance_in_cents: 0)

      expected_log = {
        "code.namespace" => "Billing::UpdatePaymentMethod",
        "code.function" => "log_outstanding_balance",
        "gh.billing.billable_entity.id" => user.id,
        "gh.billing.billable_entity.type" => user.class.name,
        "gh.billing.plan_subscription.outstanding_balance" => 25,
      }

      assert_logged(**expected_log) do
        result = update_payment_method(user, zuora_payment_method_id: zuora_new_payment_method_id)
        assert result.success?
      end

      assert_dogstats_count_value 25, "billing.update_payment_method.outstanding_balance"
    end
  end
end
