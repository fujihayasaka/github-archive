# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::Webhooks::PayoutCreatedTest < GitHub::BillingTestCase
  include HydroTestHelpers
  test "creates a payout ledger entry" do
    stripe_connect_account = create(:stripe_connect_account)
    webhook = create(
      :stripe_webhook,
      :payout_created,
      object: {
        id: "po_1",
        amount: 25_00,
      },
      account: stripe_connect_account.stripe_account_id,
    )

    assert_difference(-> { stripe_connect_account.ledger_entries.count }, 2) do
      Billing::Stripe::Webhooks::PayoutCreated.perform(webhook)
    end

    transfers_paid_ledger_entry = stripe_connect_account.ledger_entries.transfers_paid.last
    assert transfers_paid_ledger_entry
    assert_equal "transfers_paid", transfers_paid_ledger_entry.transaction_type
    assert_equal(-25_00, transfers_paid_ledger_entry.amount_in_subunits)
    assert_equal "USD", transfers_paid_ledger_entry.currency_code
    assert_equal "po_1", transfers_paid_ledger_entry.primary_reference_id

    payout_created_ledger_entry = stripe_connect_account.ledger_entries.payout.last
    assert payout_created_ledger_entry
    assert_equal "payout", payout_created_ledger_entry.transaction_type
    assert_equal 25_00, payout_created_ledger_entry.amount_in_subunits
    assert_equal "USD", payout_created_ledger_entry.currency_code
    assert_equal "po_1", payout_created_ledger_entry.primary_reference_id
  end

  test "creates a payout ledger entry if the accout was deleted" do
    stripe_connect_account = create(:stripe_connect_account, deleted_at: 1.day.ago)
    webhook = create(
      :stripe_webhook,
      :payout_created,
      object: {
        id: "po_1",
        amount: 25_00,
      },
      account: stripe_connect_account.stripe_account_id,
    )

    assert_difference(-> { stripe_connect_account.ledger_entries.count }, 2) do
      Billing::Stripe::Webhooks::PayoutCreated.perform(webhook)
    end
  end

  test "updates last_payout_at on listing for Stripe account" do
    listing = create(:sponsors_listing, :approved)
    stripe_connect_account = create(:stripe_connect_account, sponsors_listing: listing)
    payout_created = 1563305483
    webhook = create(:stripe_webhook, :payout_created, object: {
      id: "po_1", amount: 25_00, created: payout_created
    }, account: stripe_connect_account.stripe_account_id)
    assert_nil listing.last_payout_at

    Billing::Stripe::Webhooks::PayoutCreated.perform(webhook)

    assert_equal Time.at(payout_created).utc, listing.reload.last_payout_at
  end

  test "publishes a hydro event with payout details" do
    subscribe("payout.bank_payout")

    stripe_connect_account = create(:stripe_connect_account)
    payout_id = "po_1"
    webhook = create(
      :stripe_webhook,
      :payout_created,
      object: {
        id: payout_id,
        amount: 25_00,
        type: "bank_account",
      },
      account: stripe_connect_account.stripe_account_id,
    )

    Billing::Stripe::Webhooks::PayoutCreated.perform(webhook)

    assert_hydro_published({
      sponsored_maintainer: Hydro::EntitySerializer.user(stripe_connect_account.sponsorable),
      total_payout_amount_in_cents: 25_00,
      destination_account_type: :STRIPE_CONNECT,
      destination_account_id: stripe_connect_account.stripe_account_id,
      status: :CREATED,
      funding_instrument_type: :BANK_ACCOUNT,
      payout_id: payout_id,
    }, schema: "github.payouts.v0.BankPayout")
  end
end
