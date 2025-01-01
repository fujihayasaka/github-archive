# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::PayoutsLedgerTransactionTest < GitHub::BillingTestCase
  fixtures do
    @stripe_account = create(:stripe_connect_account)
  end

  test "writes ledger entries to the database" do
    transaction = Billing::PayoutsLedgerTransaction.new(@stripe_account)

    transaction.add_entry(
      transaction_type: :payment,
      amount_in_subunits: -1_00,
      currency_code: "USD",
      primary_reference_id: SecureRandom.hex(8),
    )
    transaction.add_entry(
      transaction_type: :transfer,
      amount_in_subunits: 1_00,
      currency_code: "USD",
      primary_reference_id: SecureRandom.hex(8),
    )

    assert_predicate transaction, :valid?

    assert_difference(-> { Billing::PayoutsLedgerEntry.count }, 2) do
      transaction.save!
    end
  end

  test "is invalid and raises if the entries to be written do not balance" do
    transaction = Billing::PayoutsLedgerTransaction.new(@stripe_account)

    transaction.add_entry(
      transaction_type: :payment,
      amount_in_subunits: -1_00,
      currency_code: "USD",
      primary_reference_id: SecureRandom.hex(8),
    )

    refute_predicate transaction, :valid?

    assert_difference(-> { Billing::PayoutsLedgerEntry.count }, 0) do
      assert_raises(ActiveModel::ValidationError) do
        transaction.save!
      end
    end
  end

  test "is valid but raises if the ledger is out of balance prior to writing" do
    # Put the ledger out of balance
    create(:payouts_ledger_entry, :payment, stripe_connect_account: @stripe_account)

    transaction = Billing::PayoutsLedgerTransaction.new(@stripe_account)

    transaction.add_entry(
      transaction_type: :payment,
      amount_in_subunits: -1_00,
      currency_code: "USD",
      primary_reference_id: SecureRandom.hex(8),
    )
    transaction.add_entry(
      transaction_type: :transfer,
      amount_in_subunits: 1_00,
      currency_code: "USD",
      primary_reference_id: SecureRandom.hex(8),
    )

    assert_predicate transaction, :valid?

    assert_difference(-> { Billing::PayoutsLedgerEntry.count }, 0) do
      assert_raises(Billing::PayoutsLedgerBalance::OutOfBalanceError) do
        transaction.save!
      end
    end
  end

  test "rolls back in the event of an error" do
    transaction = Billing::PayoutsLedgerTransaction.new(@stripe_account)

    transaction.add_entry(
      transaction_type: :payment,
      amount_in_subunits: -1_00,
      currency_code: "USD",
      primary_reference_id: SecureRandom.hex(8),
    )
    transaction.add_entry(
      transaction_type: :transfer,
      amount_in_subunits: 1_00,
      currency_code: "USD",
      primary_reference_id: SecureRandom.hex(8),
    )

    Billing::PayoutsLedgerEntry.any_instance.expects(:save!).raises("Boom!")

    assert_difference(-> { Billing::PayoutsLedgerEntry.count }, 0) do
      assert_raises(RuntimeError, /Boom/) { transaction.save! }
    end
  end
end if GitHub.billing_enabled?
