# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::PayoutsLedgerEntryTestCase < GitHub::BillingTestCase
  include HydroTestHelpers

  fixtures do
    @stripe_connect_account = create(:stripe_connect_account)
  end

  context "has_billing_transaction scope" do
    test "includes only ledger entries that reference a billing transaction" do
      ledger_entry_w_xact = create(:payouts_ledger_entry, :with_billing_transaction)
      ledger_entry_wo_xact = create(:payouts_ledger_entry, billing_transaction_id: nil)

      result = Billing::PayoutsLedgerEntry.has_billing_transaction

      assert_includes result, ledger_entry_w_xact
      refute_includes result, ledger_entry_wo_xact
    end
  end

  context "#sponsorable_id" do
    test "returns the sponsorable ID of the associated Sponsors listing" do
      listing = create(:sponsors_listing)
      ledger_entry = Billing::PayoutsLedgerEntry.new(sponsors_listing: listing)
      assert_equal listing.sponsorable_id, ledger_entry.sponsorable_id
    end

    test "returns nil when the Sponsors listing no longer exists" do
      ledger_entry = create(:payouts_ledger_entry)
      ledger_entry.sponsors_listing.delete
      assert_nil ledger_entry.reload.sponsorable_id
    end
  end

  context "#billing_transaction_user_id" do
    test "returns the user ID from the associated billing transaction" do
      user = create(:user)
      billing_xact = create(:billing_transaction, user: user)
      ledger_entry = build(:payouts_ledger_entry, billing_transaction: billing_xact)

      assert_equal user.id, ledger_entry.billing_transaction_user_id
    end

    test "returns nil when the ledger entry has no billing transaction" do
      ledger_entry = build(:payouts_ledger_entry, billing_transaction: nil)
      assert_nil ledger_entry.billing_transaction_user_id
    end
  end

  context "with_primary_reference_id scope" do
    test "filters to ledger entries that have a primary reference ID set" do
      entry1 = create(:payouts_ledger_entry, primary_reference_id: "123abc")
      entry2 = create(:payouts_ledger_entry, primary_reference_id: nil)

      result = Billing::PayoutsLedgerEntry.where(id: [entry1, entry2]).with_primary_reference_id

      assert_includes result, entry1
      refute_includes result, entry2
    end

    test "filters to ledger entries that have a particular primary reference ID" do
      entry1 = create(:payouts_ledger_entry, primary_reference_id: "123abc")
      entry2 = create(:payouts_ledger_entry, primary_reference_id: "8675309")

      result = Billing::PayoutsLedgerEntry.where(id: [entry1, entry2])
        .with_primary_reference_id("8675309")

      refute_includes result, entry1
      assert_includes result, entry2
    end
  end

  context "#to_money" do
    test "returns a Money for the entry's amount and currency" do
      ledger_entry = build(:payouts_ledger_entry, amount_in_subunits: -1_23,
        currency_code: "AUD")
      assert_equal ::Billing::Money.new(-1_23, "AUD"), ledger_entry.to_money
    end

    test "returns positive amount when absolute=true" do
      ledger_entry = build(:payouts_ledger_entry, amount_in_subunits: -1_23,
        currency_code: "AUD")
      assert_equal ::Billing::Money.new(1_23, "AUD"), ledger_entry.to_money(absolute: true)
    end
  end

  context ".sponsors_listing_ids_with_transfer_sum" do
    test "gets SponsorsListing IDs whose sum of transfers is less than the amount parameter" do
      transfer1 = create(:payouts_ledger_entry, :transfer, amount_in_subunits: 9)
      sponsors_listing1 = transfer1.stripe_connect_account.sponsors_listing
      transfer2 = create(:payouts_ledger_entry, :transfer, amount_in_subunits: 15)
      sponsors_listing2 = transfer2.stripe_connect_account.sponsors_listing

      listing_ids = [sponsors_listing1.id, sponsors_listing2.id]
      result = Billing::PayoutsLedgerEntry.sponsors_listing_ids_with_transfer_sum(listing_ids, :lt, 10)

      refute_empty result
      assert_equal result, [sponsors_listing1.id]
    end

    test "gets SponsorsListing IDs whose sum of transfers is greater than the amount parameter" do
      transfer1 = create(:payouts_ledger_entry, :transfer, amount_in_subunits: 25)
      sponsors_listing1 = transfer1.stripe_connect_account.sponsors_listing
      transfer2 = create(:payouts_ledger_entry, :transfer, amount_in_subunits: 20)
      sponsors_listing2 = transfer2.stripe_connect_account.sponsors_listing
      transfer3 = create(:payouts_ledger_entry, :transfer, amount_in_subunits: 15)
      sponsors_listing3 = transfer3.stripe_connect_account.sponsors_listing

      listing_ids = [sponsors_listing1.id, sponsors_listing2.id, sponsors_listing3.id]
      result = Billing::PayoutsLedgerEntry.sponsors_listing_ids_with_transfer_sum(listing_ids, :gteq, 20)

      refute_empty result
      assert_equal result, [sponsors_listing1.id, sponsors_listing2.id]
    end
  end

  context "since scope" do
    test "includes ledger entry made after the given time" do
      cutoff_time = Time.now
      ledger_entry = create(:payouts_ledger_entry, transaction_timestamp: cutoff_time)

      result = Billing::PayoutsLedgerEntry.where(id: ledger_entry)
        .since(cutoff_time - 1.hour)

      assert_equal [ledger_entry], result
    end

    test "excludes ledger entry made before the given time" do
      travel_to "2023-11-13"
      cutoff_time = Time.now
      ledger_entry = create(:payouts_ledger_entry, transaction_timestamp: cutoff_time)

      result = Billing::PayoutsLedgerEntry.where(id: ledger_entry).since(cutoff_time + 1.hour)

      assert_empty result
    end
  end

  context "sponsors_listing_transfers scope" do
    test "filters to transfers and transfer reversals that have a sponsors_listing_id set" do
      ledger_entry1 = create(:payouts_ledger_entry, :transfer)
      ledger_entry2 = create(:payouts_ledger_entry, :payment)
      ledger_entry3 = create(:payouts_ledger_entry, :transfer_reversal)
      ledger_entry4 = create(:payouts_ledger_entry, :transfer)
      ledger_entry4.update_attribute(:sponsors_listing_id, nil)

      result = Billing::PayoutsLedgerEntry.sponsors_listing_transfers
        .where(id: [ledger_entry1, ledger_entry2, ledger_entry3, ledger_entry4])

      assert_includes result, ledger_entry1
      refute_includes result, ledger_entry2, "should not include payment ledger entry"
      assert_includes result, ledger_entry3
      refute_includes result, ledger_entry4, "should not include transfer without a listing"
    end
  end

  context "since_last_sponsors_payout scope" do
    test "includes ledger entries made since the last payout for the Sponsors listing" do
      last_payout_time1 = 1.week.ago
      listing1 = create(:sponsors_listing, :with_stripe_account, last_payout_at: last_payout_time1)
      ledger_entry1 = travel_to(last_payout_time1 - 1.day) do
        create(:payouts_ledger_entry, :transfer, sponsors_listing: listing1,
          stripe_connect_account: listing1.active_stripe_connect_account)
      end
      ledger_entry2 = create(:payouts_ledger_entry, :transfer, sponsors_listing: listing1,
        stripe_connect_account: listing1.active_stripe_connect_account)

      listing2 = create(:sponsors_listing, :with_stripe_account, last_payout_at: nil)
      ledger_entry3 = create(:payouts_ledger_entry, :transfer, sponsors_listing: listing2,
        stripe_connect_account: listing2.active_stripe_connect_account)

      last_payout_time2 = 1.month.ago
      listing3 = create(:sponsors_listing, :with_stripe_account, last_payout_at: last_payout_time2)
      ledger_entry4 = travel_to(last_payout_time2 - 1.day) do
        create(:payouts_ledger_entry, :transfer, sponsors_listing: listing3,
          stripe_connect_account: listing3.active_stripe_connect_account)
      end
      ledger_entry5 = travel_to(last_payout_time2 + 1.day) do
        create(:payouts_ledger_entry, :transfer, sponsors_listing: listing3,
          stripe_connect_account: listing3.active_stripe_connect_account)
      end

      result = Billing::PayoutsLedgerEntry.where(id: [
        ledger_entry1,
        ledger_entry2,
        ledger_entry3,
        ledger_entry4,
        ledger_entry5,
      ]).since_last_sponsors_payout.pluck(:id)

      refute_includes result, ledger_entry1.id,
        "should not include ledger entry from before listing's last payout"
      assert_includes result, ledger_entry2.id,
        "should include ledger entry from after listing's last payout"
      assert_includes result, ledger_entry3.id,
        "should include ledger entry for listing that hasn't had a payout"
      refute_includes result, ledger_entry4.id,
        "should not include ledger entry from before listing's last payout"
      assert_includes result, ledger_entry5.id,
        "should include ledger entry from after listing's last payout"
    end
  end

  context "payments_for_charge_id scope" do
    test "retuns payments for a given charge id" do
      charge_id = "ch_1"
      expected_entries = create_list(:payouts_ledger_entry, 2, :payment,
        stripe_charge_id: charge_id,
      )

      assert_same_elements expected_entries, Billing::PayoutsLedgerEntry.payments_for_charge_id(charge_id)
    end

    test "does not return other transaction types or other charge ids" do
      charge_id = "ch_1"
      expected_entry = create(:payouts_ledger_entry, :payment,
        stripe_charge_id: charge_id,
      )
      create(:payouts_ledger_entry, :transfer,
        stripe_charge_id: charge_id
      )
      create(:payouts_ledger_entry, :payment,
        stripe_charge_id: "ch_other"
      )

      assert_same_elements [expected_entry], Billing::PayoutsLedgerEntry.payments_for_charge_id(charge_id)
    end
  end

  context "validations" do
    test "sets sponsors_listing_id before validation based on Stripe Connect account when listing ID is not specified" do
      listing = create(:sponsors_listing)
      stripe = create(:stripe_connect_account, sponsors_listing: listing)
      ledger_entry = Billing::PayoutsLedgerEntry.new(stripe_connect_account_id: stripe.id)

      assert_nil ledger_entry.sponsors_listing_id
      ledger_entry.valid?
      assert_equal listing.id, ledger_entry.sponsors_listing_id
    end

    test "will not override specified sponsors_listing_id" do
      listing = create(:sponsors_listing)
      stripe = create(:stripe_connect_account, sponsors_listing: listing)
      ledger_entry = Billing::PayoutsLedgerEntry.new(stripe_connect_account_id: stripe.id,
        sponsors_listing_id: listing.id + 1)

      ledger_entry.valid?
      assert_equal listing.id + 1, ledger_entry.sponsors_listing_id
    end

    test "requires the Sponsors listing relate to the Stripe account" do
      stripe = create(:stripe_connect_account)
      listing = create(:sponsors_listing)

      ledger_entry = build(:payouts_ledger_entry, sponsors_listing: listing,
        stripe_connect_account: stripe)

      refute_predicate ledger_entry, :valid?
      assert_includes ledger_entry.errors[:stripe_connect_account],
        "is not associated with #{listing.sponsorable_login}'s Sponsors profile"
    end

    test "allows using Stripe account for Sponsors listing's parent listing" do
      child_listing = create(:sponsors_listing, :with_fiscal_host)
      parent_listing = child_listing.parent_listing
      parent_stripe = create(:stripe_connect_account, sponsors_listing: parent_listing)

      ledger_entry = build(:payouts_ledger_entry, sponsors_listing: child_listing,
        stripe_connect_account: parent_stripe)

      assert_predicate ledger_entry, :valid?
    end

    test "allows using Stripe account owned by the Sponsors listing" do
      listing = create(:sponsors_listing)
      stripe = create(:stripe_connect_account, sponsors_listing: listing)

      ledger_entry = build(:payouts_ledger_entry, sponsors_listing: listing,
        stripe_connect_account: stripe)

      assert_predicate ledger_entry, :valid?
    end

    test "requires a Sponsors listing at creation time" do
      ledger_entry = Billing::PayoutsLedgerEntry.new(sponsors_listing_id: nil)
      refute_predicate ledger_entry, :valid?
      assert_includes ledger_entry.errors[:sponsors_listing_id], "must exist"
    end
  end

  context "net_transfers_with_matches scope" do
    test "includes matches, transfers, reversals, and ledger entries with no transaction type" do
      match_ledger_entry = create(:payouts_ledger_entry, :github_match)
      match_reversal_ledger_entry = create(:payouts_ledger_entry, :github_match_reversal)
      transfer_ledger_entry = create(:payouts_ledger_entry, :transfer)
      transfer_reversal_ledger_entry = create(:payouts_ledger_entry, :transfer_reversal)
      payout_ledger_entry = create(:payouts_ledger_entry, :payout)
      payout_failure_ledger_entry = create(:payouts_ledger_entry, :payout_failure)
      payment_ledger_entry = create(:payouts_ledger_entry, :payment)
      refund_ledger_entry = create(:payouts_ledger_entry, :refund)
      chargeback_ledger_entry = create(:payouts_ledger_entry, :chargeback)

      result = Billing::PayoutsLedgerEntry.net_transfers_with_matches

      assert_includes result, match_ledger_entry
      assert_includes result, match_reversal_ledger_entry
      assert_includes result, transfer_ledger_entry
      assert_includes result, transfer_reversal_ledger_entry
      refute_includes result, payout_ledger_entry
      refute_includes result, payout_failure_ledger_entry
      refute_includes result, payment_ledger_entry
      refute_includes result, refund_ledger_entry
      refute_includes result, chargeback_ledger_entry
    end
  end

  context "net_sponsors_matches scope" do
    test "includes github_match ledger entry" do
      ledger = create(:payouts_ledger_entry,
        transaction_type: :github_match,
        stripe_connect_account_id: @stripe_connect_account.id,
        primary_reference_id: "zuora_transaction_id",
      )

      assert_equal [ledger], Billing::PayoutsLedgerEntry
        .net_sponsors_matches.for_stripe_account(@stripe_connect_account.id)
    end

    test "omits transfer ledger entry" do
      ledger_transfer = create(:payouts_ledger_entry,
        transaction_type: :transfer,
        stripe_connect_account_id: @stripe_connect_account.id,
        primary_reference_id: "zuora_transaction_id",
      )

      matches_ledger = Billing::PayoutsLedgerEntry
        .net_sponsors_matches.for_stripe_account(@stripe_connect_account.id)

      refute_includes matches_ledger, ledger_transfer
    end

    test "includes match reversals" do
      ledger = create(:payouts_ledger_entry,
        transaction_type: :github_match_reversal,
        stripe_connect_account_id: @stripe_connect_account.id,
        primary_reference_id: "zuora_transaction_id",
      )

      assert_equal [ledger], Billing::PayoutsLedgerEntry
        .net_sponsors_matches.for_stripe_account(@stripe_connect_account.id)
    end

    test "omits manual transfer ledger entry" do
      manual_transfer = Billing::PayoutsLedgerEntry.create!(
        transaction_type: :manual_transfer,
        stripe_connect_account_id: @stripe_connect_account.id,
      )

      matches_ledger = Billing::PayoutsLedgerEntry
        .net_sponsors_matches.for_stripe_account(@stripe_connect_account.id)

      refute_includes matches_ledger, manual_transfer
    end
  end

  context "#instrument_early_fraud_warning" do
    test "emits Hydro event for fraud warning regarding payment" do
      payment = create(:payouts_ledger_entry, :payment)

      event = {
        stripe_fraud_id: "issfr_1",
        actionable: true,
        stripe_charge_id: "ch_1",
        stripe_timestamp: Time.at(123456789).to_datetime,
        fraud_type: :MISC,
        user_id: nil,
      }

      payment.instrument_early_fraud_warning(event)

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.EarlyFraudWarning")
    end

    test "does not emit Hydro event if transaction type is not a payment" do
      transfer = create(:payouts_ledger_entry, :transfer)

      event = {
        stripe_fraud_id: "issfr_1",
        actionable: true,
        stripe_charge_id: "ch_1",
        stripe_timestamp: Time.at(123456789).to_datetime,
        fraud_type: :MISC,
        user_id: nil,
      }

      transfer.instrument_early_fraud_warning(event)

      assert_hydro_messages(count: 0, schema: "github.sponsors.v1.EarlyFraudWarning")
    end
  end
end if GitHub.billing_enabled?
