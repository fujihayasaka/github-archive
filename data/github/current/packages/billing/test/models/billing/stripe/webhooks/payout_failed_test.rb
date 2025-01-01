# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::Webhooks::PayoutFailedTest < GitHub::BillingTestCase
  include HydroTestHelpers
  test "creates payout ledger entry" do
    stripe_connect_account = create(:stripe_connect_account)
    webhook = create(
      :stripe_webhook,
      :payout_failed,
      object: {
        id: "po_1",
        amount: 25_00,
      },
      account: stripe_connect_account.stripe_account_id,
    )

    assert_difference(-> { stripe_connect_account.ledger_entries.count }, 2) do
      Billing::Stripe::Webhooks::PayoutFailed.perform(webhook)
    end

    transfers_paid_ledger_entry = stripe_connect_account.ledger_entries.transfers_paid.last
    assert transfers_paid_ledger_entry
    assert_equal "transfers_paid", transfers_paid_ledger_entry.transaction_type
    assert_equal 25_00, transfers_paid_ledger_entry.amount_in_subunits
    assert_equal "USD", transfers_paid_ledger_entry.currency_code
    assert_equal "po_1", transfers_paid_ledger_entry.primary_reference_id

    payout_failure_ledger_entry = stripe_connect_account.ledger_entries.payout_failure.last
    assert_equal "payout_failure", payout_failure_ledger_entry.transaction_type
    assert_equal(-25_00, payout_failure_ledger_entry.amount_in_subunits)
    assert_equal "USD", payout_failure_ledger_entry.currency_code
    assert_equal "po_1", payout_failure_ledger_entry.primary_reference_id
  end

  test "creates payout ledger entry if the account was deleted" do
    stripe_connect_account = create(:stripe_connect_account, deleted_at: 1.day.ago)
    webhook = create(
      :stripe_webhook,
      :payout_failed,
      object: {
        id: "po_1",
        amount: 25_00,
      },
      account: stripe_connect_account.stripe_account_id,
    )

    assert_difference(-> { stripe_connect_account.ledger_entries.count }, 2) do
      Billing::Stripe::Webhooks::PayoutFailed.perform(webhook)
    end
  end

  test "emit metric to datadog stripe.payout_failed" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    stripe_connect_account = create(:stripe_connect_account)
    webhook = create(
      :stripe_webhook,
      :payout_failed,
      object: {
        id: "po_1",
        amount: 25_00,
      },
      account: stripe_connect_account.stripe_account_id,
    )

    Billing::Stripe::Webhooks::PayoutFailed.perform(webhook)

    increments = GitHub.dogstats.increments("stripe.payout_failed")
    assert_equal 1, increments.count
  end

  test "publishes a hydro event with payout details" do
    subscribe("payout.bank_payout")

    stripe_connect_account = create(:stripe_connect_account)
    payout_id = "po_1"
    failure_code = "invalid_account_number"
    webhook = create(
      :stripe_webhook,
      :payout_created,
      object: {
        id: payout_id,
        amount: 25_00,
        type: "bank_account",
        failure_code: failure_code,
      },
      account: stripe_connect_account.stripe_account_id,
    )

    Billing::Stripe::Webhooks::PayoutFailed.perform(webhook)

    assert_hydro_published({
      sponsored_maintainer: Hydro::EntitySerializer.user(stripe_connect_account.sponsorable),
      total_payout_amount_in_cents: 25_00,
      destination_account_type: :STRIPE_CONNECT,
      destination_account_id: stripe_connect_account.stripe_account_id,
      status: :FAILED,
      funding_instrument_type: :BANK_ACCOUNT,
      payout_id: payout_id,
      failure_code: failure_code,
    }, schema: "github.payouts.v0.BankPayout")
  end
end
