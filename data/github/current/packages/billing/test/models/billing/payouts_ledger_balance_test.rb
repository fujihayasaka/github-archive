# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::PayoutsLedgerBalanceTest < GitHub::BillingTestCase
  fixtures do
    @stripe_account = create(:stripe_connect_account)
  end

  def ledger_balance
    Billing::PayoutsLedgerBalance.new(@stripe_account)
  end

  context "#in_balance?" do
    test "is in balance after payment, match, transfer" do
      create(:payouts_ledger_entry, :payment, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :github_match, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :transfer, amount_in_subunits: 2_00, stripe_connect_account: @stripe_account)

      assert_predicate ledger_balance, :in_balance?
    end

    test "is in balance after payment, match, transfer, and payout" do
      create(:payouts_ledger_entry, :payment, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :github_match, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :transfer, amount_in_subunits: 2_00, stripe_connect_account: @stripe_account)

      create(:payouts_ledger_entry, :transfers_paid, amount_in_subunits: -2_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :payout, amount_in_subunits: 2_00, stripe_connect_account: @stripe_account)

      assert_predicate ledger_balance, :in_balance?
    end

    test "is in balance after payment, match, transfer, and refund" do
      create(:payouts_ledger_entry, :payment, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :github_match, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :transfer, amount_in_subunits: 2_00, stripe_connect_account: @stripe_account)

      create(:payouts_ledger_entry, :transfer_reversal, amount_in_subunits: -2_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :github_match_reversal, amount_in_subunits: 1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :refund, amount_in_subunits: 1_00, stripe_connect_account: @stripe_account)

      assert_predicate ledger_balance, :in_balance?
    end

    test "is in balance after payment, match, transfer, and chargeback" do
      create(:payouts_ledger_entry, :payment, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :github_match, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :transfer, amount_in_subunits: 2_00, stripe_connect_account: @stripe_account)

      create(:payouts_ledger_entry, :transfer_reversal, amount_in_subunits: -2_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :github_match_reversal, amount_in_subunits: 1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :chargeback, amount_in_subunits: 1_00, stripe_connect_account: @stripe_account)

      assert_predicate ledger_balance, :in_balance?
    end

    test "is in balance after payment, match, transfer, chargeback, and chargeback reversal" do
      create(:payouts_ledger_entry, :payment, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :github_match, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :transfer, amount_in_subunits: 2_00, stripe_connect_account: @stripe_account)

      create(:payouts_ledger_entry, :transfer_reversal, amount_in_subunits: -2_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :github_match_reversal, amount_in_subunits: 1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :chargeback, amount_in_subunits: 1_00, stripe_connect_account: @stripe_account)

      create(:payouts_ledger_entry, :chargeback_reversal, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :transfer, amount_in_subunits: 1_00, stripe_connect_account: @stripe_account)

      assert_predicate ledger_balance, :in_balance?
    end

    test "is in balance after payment, match, transfer, payout, and payout failure" do
      create(:payouts_ledger_entry, :payment, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :github_match, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :transfer, amount_in_subunits: 2_00, stripe_connect_account: @stripe_account)

      create(:payouts_ledger_entry, :transfers_paid, amount_in_subunits: -2_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :payout, amount_in_subunits: 2_00, stripe_connect_account: @stripe_account)

      create(:payouts_ledger_entry, :payout_failure, amount_in_subunits: -2_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :transfers_paid, amount_in_subunits: 2_00, stripe_connect_account: @stripe_account)

      assert_predicate ledger_balance, :in_balance?
    end

    test "is in balance after match, and manual transfer" do
      create(:payouts_ledger_entry, :github_match, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :manual_transfer, amount_in_subunits: 1_00, stripe_connect_account: @stripe_account)

      assert_predicate ledger_balance, :in_balance?
    end

    test "is out of balance if the transfer fails" do
      create(:payouts_ledger_entry, :payment, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :github_match, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)

      refute_predicate ledger_balance, :in_balance?
    end
  end

  context "#ensure_in_balance" do
    test "returns true for an in-balance ledger" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      create(:payouts_ledger_entry, :payment, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :github_match, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :transfer, amount_in_subunits: 2_00, stripe_connect_account: @stripe_account)

      assert_no_difference(-> { Billing::PayoutsLedgerDiscrepancy.count }) do
        assert ledger_balance.ensure_in_balance
      end
    end

    test "returns false and reports to Datadog for an out-of-balance ledger" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      create(:payouts_ledger_entry, :payment, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)

      assert_difference(-> { Billing::PayoutsLedgerDiscrepancy.count }, 1) do
        refute ledger_balance.ensure_in_balance
      end

      discrepancy = Billing::PayoutsLedgerDiscrepancy.last
      assert_predicate discrepancy, :unresolved?
      assert_equal @stripe_account, T.must(discrepancy).stripe_connect_account
      assert_equal(-1_00, T.must(discrepancy).discrepancy_in_subunits)
    end
  end

  context "#ensure_in_balance!" do
    test "does not raise for an in-balance ledger" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      create(:payouts_ledger_entry, :payment, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :github_match, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)
      create(:payouts_ledger_entry, :transfer, amount_in_subunits: 2_00, stripe_connect_account: @stripe_account)

      assert_no_difference(-> { Billing::PayoutsLedgerDiscrepancy.count }) do
        # Implicit assertion: No Billing::PayoutsLedgerBalance::OutOfBalanceError is raised
        ledger_balance.ensure_in_balance!
      end
    end

    test "returns false and reports to Datadog for an out-of-balance ledger" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      create(:payouts_ledger_entry, :payment, amount_in_subunits: -1_00, stripe_connect_account: @stripe_account)

      assert_difference(-> { Billing::PayoutsLedgerDiscrepancy.count }, 1) do
        assert_raises(Billing::PayoutsLedgerBalance::OutOfBalanceError) do
          ledger_balance.ensure_in_balance!
        end
      end

      discrepancy = Billing::PayoutsLedgerDiscrepancy.last
      assert_predicate discrepancy, :unresolved?
      assert_equal @stripe_account, T.must(discrepancy).stripe_connect_account
      assert_equal(-1_00, T.must(discrepancy).discrepancy_in_subunits)
    end
  end
end if GitHub.billing_enabled?
