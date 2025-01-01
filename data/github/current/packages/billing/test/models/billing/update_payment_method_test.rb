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

    GitHub::Billing::ZuoraPaypal.expects(:create_payment_method).never

    result = update_payment_method(user, { paypal_nonce: paypal_nonce, billing_address: billing_address })

    refute_predicate result, :success?
    assert_equal "You must cancel your recurring sponsorship first before you can switch to PayPal.",
      result.error_message
  end if GitHub.sponsors_enabled?

  test "disallows changing to PayPal when org sponsor has active sponsorships" do
    org = create(:organization)
    customer_account = create(:credit_card_customer_account, :zuora, user: org)
    create(:billing_plan_subscription, :zuora, user: org)
    create_pair(:sponsorship, sponsor: org)
    paypal_nonce = "4a70cbae-dbe2-0edf-02e8-63f52219ec2b"
    billing_address = { country_code_alpha3: "USA", region: "New York", postal_code: "10036" }

    GitHub::Billing::ZuoraPaypal.expects(:create_payment_method).never

    result = update_payment_method(org, { paypal_nonce: paypal_nonce, billing_address: billing_address })

    refute_predicate result, :success?
    assert_equal "You must cancel @#{org}'s 2 recurring sponsorships first before you can switch to PayPal.",
      result.error_message
  end if GitHub.sponsors_enabled?

  test "optionally defers the charge" do
    with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
      user = create(:user, billed_on: ::GitHub::Billing.today - 2.days)

      zuora_successful_customer_account_creation(user)
      user.reload

      assert_no_enqueued_jobs(only: BillingChargeJob) do
        result = update_payment_method(user, zuora_payment_method_id: zuora_new_payment_method_id, charge: false)
        assert result.success?
      end
      assert_equal 0, ActionMailer::Base.deliveries.size
      assert_equal ::GitHub::Billing.today - 2.days, user.reload.billed_on
    end
  end

  test "prevents updating payment method if the user has been spam-flagged" do
    user = create(:credit_card_user)
    user.stubs(:spammy?).returns(true)
    response = update_payment_method(user, zuora_payment_method_id: zuora_new_payment_method_id)
    assert response.failed?
    assert_match /This account has been flagged. #{GitHub.support_link_text} for further information./, response.error_message
  end

  test "unlocks billing for disabled users who should be enabled and unlock_billing: true is passed" do
    with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
      user = create :user, billing_attempts: 0
      zuora_successful_customer_account_creation(user)
      user.reload
      user.update(disabled: true)

      refute user.should_disable?

      result = update_payment_method(user, zuora_parsed_payment_details, unlock_billing: true)

      assert result.success?

      assert_predicate user, :enabled?
      assert_equal 0, user.billing_attempts
    end
  end

  test "does not unlock billing for disabled users when unlock_billing is not passed" do
    with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
      user = create :user
      zuora_successful_customer_account_creation(user)
      user.reload
      user.update(disabled: true, billing_attempts: 1)

      result = update_payment_method(user, zuora_parsed_payment_details)

      assert result.success?

      refute_predicate user, :enabled?
      assert_equal 1, user.billing_attempts
    end
  end

  test "does not unlock billing for disabled users who should remain disabled" do
    with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
      user = create :user
      zuora_successful_customer_account_creation(user)
      user.reload
      user.update(disabled: true, billing_attempts: 15)

      assert user.should_disable?

      result = update_payment_method(user, zuora_parsed_payment_details, unlock_billing: true)

      assert result.success?

      refute_predicate user, :enabled?
      assert_equal 15, user.billing_attempts
    end
  end

  test "enqueues an authorization check for users disabled by an authorization failure when unlock_billing: true" do
    user = create :credit_card_user, billing_attempts: 0, plan_subscription: create(:billing_plan_subscription, :zuora)
    create(:billing_budget, owner: user)

    zuora_successful_customer_account_creation(user)
    user.reload
    user.disable!(reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure)

    # The authorization amount depends on the amount of metered usage, test all scenarios
    [[0, 100], [1, 2000], [50000, 10000]].each do |metered_usage_amount_in_cents, authorization_amount_in_cents|
      with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
        Billing::UsageChecker.any_instance.stubs(:total_usage_in_cents).returns(metered_usage_amount_in_cents)
        args = {
          entity_id: user.id,
          amount_in_cents: authorization_amount_in_cents,
          unlock_billing_on_success: true,
          reset_billing_attempts_when_unlocked: true,
          is_business: false,
          origin: "Billing::UpdatePaymentMethod"
        }
        assert_enqueued_with job: Billing::CreateAuthorizationBillingTransactionJob, args: [args] do
          result = update_payment_method(user, zuora_parsed_payment_details, unlock_billing: true)
          assert result.success?
        end
        Billing::UsageChecker.unstub(:total_paid_usage_for)
      end
    end
  end

  test "enqueues an authorization check for non trusted organization when copilot_auth_on_payment_method_update is enabled" do
    GitHub.flipper[:copilot_auth_on_payment_method_update].enable

    org = create :credit_card_org, billing_attempts: 0, plan_subscription: create(:billing_plan_subscription, :zuora)
    create(:billing_budget, owner: org)
    seat_assignment = create(:copilot_seat_assignment, organization: org, assignable: org.admins.first, assigning_user: org.admins.first)
    seat_assignment.convert_to_seats
    org.settings.set!(:trust_tier, TrustTiers::Tier::NEUTRAL)

    zuora_successful_customer_account_creation(org)
    org.reload
    org.disable!(reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure)

    # The authorization amount depends on the amount of metered usage, copilot seats and trust tier
    [[0, 1900], [1, 2000], [50000, 10000]].each do |metered_usage_amount_in_cents, authorization_amount_in_cents|
      with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
        Billing::UsageChecker.any_instance.stubs(:total_usage_in_cents).returns(metered_usage_amount_in_cents)
        args = {
          entity_id: org.id,
          amount_in_cents: authorization_amount_in_cents,
          unlock_billing_on_success: true,
          reset_billing_attempts_when_unlocked: true,
          is_business: false,
          origin: "Billing::UpdatePaymentMethod"
        }
        assert_enqueued_with job: Billing::CreateAuthorizationBillingTransactionJob, args: [args] do
          result = update_payment_method(org, zuora_parsed_payment_details, unlock_billing: true)
          assert result.success?
        end
        Billing::UsageChecker.unstub(:total_paid_usage_for)
      end
    end
  end

  test "doesn't enqueue an authorization check for trusted organization when copilot_auth_on_payment_method_update is enabled" do
    GitHub.flipper[:copilot_auth_on_payment_method_update].enable

    org = create :credit_card_org, billing_attempts: 0, plan_subscription: create(:billing_plan_subscription, :zuora)
    seat_assignment = create(:copilot_seat_assignment, organization: org, assignable: org.admins.first, assigning_user: org.admins.first)
    seat_assignment.convert_to_seats
    create(:billing_budget, owner: org)
    org.settings.set!(:trust_tier, TrustTiers::Tier::TRUSTED)

    zuora_successful_customer_account_creation(org)
    org.reload
    org.disable!(reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure)

    # The authorization amount depends on the amount of metered usage, copilot seats and trust tier
    [[0, 100], [1, 2000], [50000, 10000]].each do |metered_usage_amount_in_cents, authorization_amount_in_cents|
      with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
        Billing::UsageChecker.any_instance.stubs(:total_usage_in_cents).returns(metered_usage_amount_in_cents)
        args = {
          entity_id: org.id,
          amount_in_cents: authorization_amount_in_cents,
          unlock_billing_on_success: true,
          reset_billing_attempts_when_unlocked: true,
          is_business: false,
          origin: "Billing::UpdatePaymentMethod"
        }
        assert_enqueued_with job: Billing::CreateAuthorizationBillingTransactionJob, args: [args] do
          result = update_payment_method(org, zuora_parsed_payment_details, unlock_billing: true)
          assert result.success?
        end
        Billing::UsageChecker.unstub(:total_paid_usage_for)
      end
    end
  end

  test "authorization amount for untrusted copilot organization isn't proportional to seats when copilot_auth_on_payment_method_update is disabled" do
    GitHub.flipper[:copilot_auth_on_payment_method_update].disable

    org = create :credit_card_org, billing_attempts: 0, plan_subscription: create(:billing_plan_subscription, :zuora)
    seat_assignment = create(:copilot_seat_assignment, organization: org, assignable: org.admins.first, assigning_user: org.admins.first)
    seat_assignment.convert_to_seats
    create(:billing_budget, owner: org)
    org.settings.set!(:trust_tier, TrustTiers::Tier::NEUTRAL)

    zuora_successful_customer_account_creation(org)
    org.reload
    org.disable!(reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure)

    # The authorization amount depends on the amount of metered usage, copilot seats and trust tier
    [[0, 100], [1, 2000], [50000, 10000]].each do |metered_usage_amount_in_cents, authorization_amount_in_cents|
      with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
        Billing::UsageChecker.any_instance.stubs(:total_usage_in_cents).returns(metered_usage_amount_in_cents)
        args = {
          entity_id: org.id,
          amount_in_cents: authorization_amount_in_cents,
          unlock_billing_on_success: true,
          reset_billing_attempts_when_unlocked: true,
          is_business: false,
          origin: "Billing::UpdatePaymentMethod"
        }
        assert_enqueued_with job: Billing::CreateAuthorizationBillingTransactionJob, args: [args] do
          result = update_payment_method(org, zuora_parsed_payment_details, unlock_billing: true)
          assert result.success?
        end
        Billing::UsageChecker.unstub(:total_paid_usage_for)
      end
    end
  end

  test "enqueues an authorization check for users disabled on the free plan when unlock_billing: true" do
    user = create :credit_card_user, plan_subscription: create(:billing_plan_subscription)
    create(:billing_budget, owner: user)

    zuora_successful_customer_account_creation(user)
    user.reload
    user.update_columns(disabled: true, billing_attempts: 3, billed_on: GitHub::Billing.today - 2.weeks)

    assert user.plan.free?
    assert user.should_disable?
    assert user.payment_amount.zero?

    # The authorization amount depends on the amount of metered usage, test all scenarios
    [[0, 100], [1, 2000], [50000, 10000]].each do |metered_usage_amount_in_cents, authorization_amount_in_cents|
      with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
        Billing::UsageChecker.any_instance.stubs(:total_paid_usage_for).returns(metered_usage_amount_in_cents)
        args = {
          entity_id: user.id,
          amount_in_cents: authorization_amount_in_cents,
          unlock_billing_on_success: true,
          reset_billing_attempts_when_unlocked: true,
          is_business: false,
          origin: "Billing::UpdatePaymentMethod"
        }
        assert_enqueued_with job: Billing::CreateAuthorizationBillingTransactionJob, args: [args] do
          result = update_payment_method(user, zuora_parsed_payment_details, unlock_billing: true)
          assert result.success?
        end
        Billing::UsageChecker.unstub(:total_paid_usage_for)
      end
    end
  end

  test "does not enqueue an authorization check when unlock_billing is not passed" do
    with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
      user = create :credit_card_user, plan_subscription: create(:billing_plan_subscription, :zuora)
      create(:billing_budget, owner: user)

      zuora_successful_customer_account_creation(user)
      user.reload
      user.update_columns(disabled: true, billing_attempts: 3, billed_on: GitHub::Billing.today - 2.weeks)

      assert_no_enqueued_jobs(only: Billing::CreateAuthorizationBillingTransactionJob) do
        result = update_payment_method(user, zuora_parsed_payment_details)
        assert result.success?
      end

      refute_predicate user, :enabled?
      assert_equal 3, user.billing_attempts
    end
  end

  test "does not enqueue an authorization check when the user is disabled on a paid plan with no external subscription" do
    with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
      user = create :credit_card_user, plan: "pro", billing_attempts: 0, plan_subscription: create(:billing_plan_subscription)
      create(:billing_budget, owner: user)

      zuora_successful_customer_account_creation(user)
      user.reload
      user.update_columns(disabled: true, billing_attempts: 3, billed_on: GitHub::Billing.today - 2.weeks)

      assert_no_enqueued_jobs(only: Billing::CreateAuthorizationBillingTransactionJob) do
        result = update_payment_method(user, zuora_parsed_payment_details, unlock_billing: true)
        assert result.success?
      end
    end
  end

  test "does not enqueue an authorization check when the user does not have their billing locked" do
    with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
      user = create :credit_card_user, billing_attempts: 0, plan_subscription: create(:billing_plan_subscription, :zuora)
      create(:billing_budget, owner: user)

      zuora_successful_customer_account_creation(user)
      user.reload
      assert_predicate user, :enabled?

      assert_no_enqueued_jobs(only: Billing::CreateAuthorizationBillingTransactionJob) do
        result = update_payment_method(user, zuora_parsed_payment_details, unlock_billing: true)
        assert result.success?
      end
    end
  end

  test "unlocks billing for business disabled due to recurring charge when unlock_billing: true is passed" do
    with_live_zuora("zuora/successful_update_enterprise_credit_card") do
      owner = create :user
      business = create :business, owners: [owner]
      business.customer.update!(
        billing_type: ::Customer::BILLING_TYPE_CARD,
        billing_attempts: 3,
        billing_end_date: 3.weeks.ago
      )
      zuora_successful_customer_account_creation business
      business.downgrade_to_free_plan
      business.reload
      assert_predicate business, :disabled?
      assert_predicate business, :disabled_due_to_failed_recurring_charge?

      result = update_payment_method business, zuora_parsed_payment_details.merge(actor: owner), unlock_billing: true
      assert_predicate result, :success?

      business.reload
      assert_predicate business, :enabled?
      assert_equal 0, business.billing_attempts
    end
  end

  test "does not unlock billing for business disabled due to recurring charge when unlock_billing: false is passed" do
    with_live_zuora("zuora/successful_update_enterprise_credit_card") do
      owner = create :user
      business = create :business, owners: [owner]
      business.customer.update!(
        billing_type: ::Customer::BILLING_TYPE_CARD,
        billing_attempts: 3,
        billing_end_date: 3.weeks.ago
      )
      zuora_successful_customer_account_creation business
      business.downgrade_to_free_plan
      business.reload
      assert_predicate business, :disabled?
      assert_predicate business, :disabled_due_to_failed_recurring_charge?

      result = update_payment_method business, zuora_parsed_payment_details.merge(actor: owner), unlock_billing: false
      assert_predicate result, :success?

      business.reload
      assert_predicate business.reload, :disabled?
      assert_equal 3, business.billing_attempts
    end
  end

  test "successful response when updating a credit card" do
    with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
      user = create(:user)

      zuora_successful_customer_account_creation(user)
      user.reload

      assert_enqueued_jobs 1, only: BillingChargeJob do
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
