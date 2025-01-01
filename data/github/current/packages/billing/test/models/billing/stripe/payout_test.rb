# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::PayoutTestCase < GitHub::BillingTestCase
  test "should special case subunits for hungarian forint currency" do
    stripe_payout = Stripe::Payout.construct_from(id: "po_8675309", amount: 360_00, currency: "huf",
      created: 1616288570)

    billing_payout = Billing::Stripe::Payout.new(stripe_payout: stripe_payout, stripe_account_id: "acct_123abc")

    assert_equal billing_payout.amount, 360
  end

  test "does not special case subunits for usd" do
    stripe_payout = Stripe::Payout.construct_from(id: "po_8675309", amount: 360_00, currency: "usd",
      created: 1616288570)

    billing_payout = Billing::Stripe::Payout.new(stripe_payout: stripe_payout, stripe_account_id: "acct_123abc")

    assert_equal billing_payout.amount, 360_00
  end

  test "should delegate properties to stripe_payout" do
    account_id = "acct_thx1138"
    stripe_payout = Stripe::Payout.construct_from(id: "po_8675309", amount: 100_00, currency: "usd",
      created: 1616288570, arrival_date: 1616288570, destination: account_id, statement_descriptor: "sponsors",
      status: "pending", failure_code: nil)

    billing_payout = Billing::Stripe::Payout.new(stripe_payout: stripe_payout, stripe_account_id: account_id)
    assert_equal billing_payout.id, stripe_payout.id
    assert_equal billing_payout.created, stripe_payout.created
    assert_equal billing_payout.currency, stripe_payout.currency
    assert_equal billing_payout.arrival_date, stripe_payout.arrival_date
    assert_equal billing_payout.destination, stripe_payout.destination
    assert_equal billing_payout.statement_descriptor, stripe_payout.statement_descriptor
    assert_equal billing_payout.status, stripe_payout.status
    assert_nil billing_payout.failure_code
  end
end
