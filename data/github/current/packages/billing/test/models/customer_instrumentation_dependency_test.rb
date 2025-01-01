# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomerInstrumentationDependencyTest < GitHub::TestCase
  context "#track_lock_billing" do
    test "lock billing for a customer with no billable owner" do
      events = subscribe("billing.lock")
      customer = create(:customer)
      assert_nil customer.billable_owner

      customer.lock_billing(reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure)

      expected_payload = {
        customer_id: customer.id,
        locked_at: customer.locked_at,
        lock_reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure.serialize,
      }
      assert_equal(expected_payload, events.pop.payload)
    end

    test "lock billing for a user" do
      events = subscribe("billing.lock")
      user = create(:credit_card_user)

      user.disable!(reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure)

      customer = user.customer
      expected_payload = {
        customer_id: customer.id,
        locked_at: customer.locked_at,
        billed_on: user.billed_on,
        billing_attempts: 0,
        plan: user.plan.name,
        lock_reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure.serialize,
        user: user.display_login,
        user_id: user.id
      }
      assert_equal(expected_payload, events.pop.payload)
    end

    test "lock billing for a business", skip_enterprise: true do
      events = subscribe("billing.lock")
      business = create(:business, :with_credit_card)

      business.disable!(reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure)

      customer = business.customer
      expected_payload = {
        customer_id: customer.id,
        locked_at: customer.locked_at,
        billed_on: business.billed_on,
        billing_attempts: 0,
        plan: business.plan.name,
        lock_reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure.serialize,
        business: business.slug,
        business_id: business.id
      }
      assert_equal(expected_payload, events.pop.payload)
    end
  end

  context "#track_unlock_billing" do
    test "unlock billing for a customer with no billable owner" do
      events = subscribe("billing.unlock")
      customer = create(:customer, locked_at: Time.now, disabled_reasons: Set.new(["some_reason"]))
      locked_at = customer.locked_at
      disabled_reasons = customer.disabled_reasons
      assert_nil customer.billable_owner

      customer.unlock_billing

      expected_payload = {
        customer_id: customer.id,
        previously_locked_at: locked_at,
        previously_disabled_reasons: disabled_reasons,
      }
      assert_equal(expected_payload, events.pop.payload)
    end

    test "unlock billing for a user" do
      events = subscribe("billing.unlock")
      user = create(:credit_card_user)

      user.disable!(reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure)

      customer = user.customer
      locked_at = customer.locked_at
      disabled_reasons = customer.disabled_reasons

      user.enable!

      expected_payload = {
        customer_id: customer.id,
        billed_on: user.billed_on,
        billing_attempts: 0,
        plan: user.plan.name,
        user: user.display_login,
        user_id: user.id,
        previously_locked_at: locked_at,
        previously_disabled_reasons: disabled_reasons,
      }
      assert_equal(expected_payload, events.pop.payload)
    end

    test "unlock billing for a business", skip_enterprise: true do
      events = subscribe("billing.unlock")
      business = create(:business, :with_credit_card)

      business.disable!(reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure)

      customer = business.customer
      locked_at = customer.locked_at
      disabled_reasons = customer.disabled_reasons

      business.enable!

      expected_payload = {
        customer_id: customer.id,
        billed_on: business.billed_on,
        billing_attempts: 0,
        plan: business.plan.name,
        business: business.slug,
        business_id: business.id,
        previously_locked_at: locked_at,
        previously_disabled_reasons: disabled_reasons,
      }
      assert_equal(expected_payload, events.pop.payload)
    end
  end
end
