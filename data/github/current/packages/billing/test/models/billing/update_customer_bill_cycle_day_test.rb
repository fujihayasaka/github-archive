# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::UpdateCustomerBillCycleDayTest < GitHub::BillingTestCase
  test "updates bill cycle day for credit card user but doesn't sync the subscription when current bcd is less than today" do
    travel_to Time.zone.local(2023, 10, 10, 1, 0, 0)
    user = create(:credit_card_user)
    user.customer.update!(bill_cycle_day: 3)
    plan_subscription = create(:billing_plan_subscription, :zuora, balance_in_cents: 7_00, user: user)

    result = ::Billing::UpdateCustomerBillCycleDay.new(user, 1).call

    user.reload

    assert result.success?
    assert_equal 1, user.customer_bill_cycle_day
  end

  test "updates bill cycle day for a business but doesn't sync subscription when current bcd is less than today" do
    travel_to Time.zone.local(2023, 10, 10, 1, 0, 0)
    business = create(:business, :with_self_serve_payment)
    business.customer.update!(bill_cycle_day: 3)
    plan_subscription = create(:billing_plan_subscription, :zuora, balance_in_cents: 7_00, user: nil, customer: business.customer)

    result = ::Billing::UpdateCustomerBillCycleDay.new(business, 1).call

    business.reload

    assert result.success?
    assert_equal 1, business.customer_bill_cycle_day
  end

  test "don't update bill cycle day for normal user" do
    user = create(:user)

    result = ::Billing::UpdateCustomerBillCycleDay.new(user, 7).call

    user.reload

    assert_equal 0, user.customer_bill_cycle_day
    refute result.success?
    assert_equal "User has no customer", result.error_message
  end

  test "don't update bill cycle day for a business without a customer" do
    business = create(:business, customer: nil) # business factory creates a customer by default

    result = ::Billing::UpdateCustomerBillCycleDay.new(business, 7).call

    business.reload

    assert_equal 0, business.customer_bill_cycle_day
    refute result.success?
    assert_equal "Business has no customer", result.error_message
  end

  test "don't update if bill cycle day is invalid" do
    user = create(:credit_card_user)

    result = ::Billing::UpdateCustomerBillCycleDay.new(user, 50).call

    refute result.success?
    assert_equal "Bill cycle day should be from 0 - 31", result.error_message
  end

  test "updates if customer is on vNext" do
    travel_to Time.zone.local(2023, 10, 10, 1, 0, 0)
    user = create(:credit_card_user)
    user.customer.update!(bill_cycle_day: 1, billed_via_billing_platform: true)

    plan_subscription = create(:billing_plan_subscription, :zuora, balance_in_cents: 7_00, user: user)

    result = ::Billing::UpdateCustomerBillCycleDay.new(user, 7).call

    user.reload

    assert result.success?
    assert_equal 7, user.customer_bill_cycle_day
  end

  test "instruments an audit log event for a user" do
    events = subscribe "billing.update_bill_cycle_day"

    user = create(:credit_card_user)

    ::Billing::UpdateCustomerBillCycleDay.new(user, 7).call

    expected_payload = {
      old_bill_cycle_day: 0,
      new_bill_cycle_day: 7,
      user: user.login,
      user_id: user.id
    }
    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "instruments an audit log event for a business" do
    events = subscribe "billing.update_bill_cycle_day"

    business = create(:business)
    old_bill_cycle_day = business.customer_bill_cycle_day

    ::Billing::UpdateCustomerBillCycleDay.new(business, 7).call

    expected_payload = {
      old_bill_cycle_day: old_bill_cycle_day,
      new_bill_cycle_day: 7,
      business: business.slug,
      business_id: business.id
    }
    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "updates sponsors bill cycle day for sponsors invoiced org when sponsors-purpose is passed in" do
    sponsors_invoiced_org = create(:invoiced_organization, :sponsors_invoiced)
    sponsors_invoiced_org.sponsors_customer.update!(bill_cycle_day: 3)
    sponsors_invoiced_org.customer.update!(bill_cycle_day: 3)

    result = ::Billing::UpdateCustomerBillCycleDay.new(sponsors_invoiced_org, 1, purpose: :sponsors).call

    sponsors_invoiced_org.reload

    assert_predicate result, :success?
    assert_equal 3, sponsors_invoiced_org.customer_bill_cycle_day
    assert_equal 1, sponsors_invoiced_org.sponsors_customer_bill_cycle_day
  end
end
