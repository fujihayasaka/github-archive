# typed: true
# frozen_string_literal: true

require "test_helper"

class InvoicedSponsorshipTransferTest < GitHub::TestCase
  fixtures do
    @completed_transfer = create(:invoiced_sponsorship_transfer, :completed)
    @completed_ledger_entry = create(:payouts_ledger_entry, :transfer,
      amount_in_subunits: @completed_transfer.amount_in_cents,
      stripe_connect_account: @completed_transfer.stripe_connect_account,
      sponsors_listing: @completed_transfer.sponsors_listing,
      primary_reference_id: @completed_transfer.stripe_transfer_id)
    @incomplete_transfer = create(:invoiced_sponsorship_transfer)
    @incomplete_transfer_sponsorship = create(:sponsorship, :invoiced,
      invoiced_sponsorship_transfer: @incomplete_transfer)
  end

  context "#to_money" do
    test "returns a Billing::Money object with the transfer's amount" do
      transfer = InvoicedSponsorshipTransfer.new(amount_in_cents: 5_000_00)
      assert_equal Billing::Money.new(5_000_00), transfer.to_money
    end
  end

  context "for_sponsorable scope" do
    test "includes transfers made to the specified sponsorable" do
      sponsorable = @completed_transfer.sponsorable
      refute_equal sponsorable, @incomplete_transfer.sponsorable, "need transfers with two different sponsorables"
      incomplete_transfer_from_sponsorable = create(:invoiced_sponsorship_transfer,
        sponsors_listing: @completed_transfer.sponsors_listing)

      result = InvoicedSponsorshipTransfer.for_sponsorable(sponsorable)

      assert_includes result, @completed_transfer
      refute_includes result, @incomplete_transfer
      assert_includes result, incomplete_transfer_from_sponsorable
    end
  end

  context "#consecutive_recurrence?" do
    test "returns true for transfer directly following a similar one" do
      transfer1 = create(:invoiced_sponsorship_transfer, :completed)
      transfer2 = travel_to(transfer1.created_at + Sponsorship::DAYS_TO_SHOW_ONE_TIME_SPONSORS.days) do
        create(:invoiced_sponsorship_transfer, :completed, sponsor: transfer1.sponsor,
          sponsors_listing: transfer1.sponsors_listing)
      end
      assert_predicate transfer2, :consecutive_recurrence?
    end

    test "returns false for transfer with no preceding similar transfers" do
      transfer = create(:invoiced_sponsorship_transfer, :completed)
      refute_predicate transfer, :consecutive_recurrence?
    end

    test "returns false for transfer with preceding similar transfer that wasn't consecutive" do
      transfer1 = create(:invoiced_sponsorship_transfer, :completed)
      transfer2 = travel_to(transfer1.created_at + (Sponsorship::DAYS_TO_SHOW_ONE_TIME_SPONSORS * 2).days) do
        create(:invoiced_sponsorship_transfer, :completed, sponsor: transfer1.sponsor,
          sponsors_listing: transfer1.sponsors_listing)
      end
      refute_predicate transfer2, :consecutive_recurrence?
    end
  end

  context "#record_stripe_transfer" do
    test "sets transfer_created_at and Stripe transfer ID on transfer and updates sponsorship paid_at" do
      travel_to "2023-11-13"
      time = Time.now.utc
      transfer_id = "tr_1G77IOEQsq43iHhXZmQb0ecK"
      assert_nil @incomplete_transfer.transfer_created_at
      assert_nil @incomplete_transfer.stripe_transfer_id
      assert_nil @incomplete_transfer_sponsorship.paid_at

      assert @incomplete_transfer.record_stripe_transfer(time: time, transfer_id: transfer_id)

      assert_equal time.to_i, @incomplete_transfer.reload.transfer_created_at.to_i
      assert_equal transfer_id, @incomplete_transfer.stripe_transfer_id
      assert_equal time.to_i, @incomplete_transfer_sponsorship.reload.paid_at.to_i
    end

    test "sets transfer_created_at and Stripe transfer ID on transfer even when no sponsorship exists" do
      travel_to "2023-11-13"
      @incomplete_transfer_sponsorship.delete
      time = Time.now.utc
      transfer_id = "tr_1G77IOEQsq43iHhXZmQb0ecK"
      assert_nil @incomplete_transfer.transfer_created_at
      assert_nil @incomplete_transfer.stripe_transfer_id

      assert @incomplete_transfer.record_stripe_transfer(time: time, transfer_id: transfer_id)

      assert_equal time.to_i, @incomplete_transfer.reload.transfer_created_at.to_i
      assert_equal transfer_id, @incomplete_transfer.stripe_transfer_id
    end

    test "does not change sponsorship paid_at when transfer update fails" do
      InvoicedSponsorshipTransfer.any_instance.stubs(:update).returns(false)
      refute @incomplete_transfer.record_stripe_transfer(time: Time.now, transfer_id: "tr_123")
      assert_nil @incomplete_transfer_sponsorship.reload.paid_at
    end

    test "rolls back transfer update when sponsorship update fails" do
      Sponsorship.any_instance.stubs(:update).returns(false)

      refute @incomplete_transfer.record_stripe_transfer(time: Time.now, transfer_id: "tr_123")

      assert_nil @incomplete_transfer.reload.transfer_created_at
      assert_nil @incomplete_transfer.stripe_transfer_id
    end
  end

  context "#ledger_entries" do
    test "includes ledger entries for the transfer's Sponsors listing, Stripe account, and Stripe transfer" do
      assert_includes @completed_transfer.ledger_entries, @completed_ledger_entry
    end

    test "excludes ledger entry for a different Stripe account" do
      other_stripe = create(:stripe_connect_account, :inactive,
        sponsors_listing: @completed_transfer.sponsors_listing)
      ledger_entry = create(:payouts_ledger_entry, :transfer,
        stripe_connect_account: other_stripe,
        sponsors_listing: @completed_transfer.sponsors_listing,
        primary_reference_id: @completed_transfer.stripe_transfer_id)

      result = @completed_transfer.ledger_entries

      refute_includes result, ledger_entry
    end

    test "excludes ledger entry for a different Stripe transfer" do
      ledger_entry = create(:payouts_ledger_entry, :transfer,
        stripe_connect_account: @completed_transfer.stripe_connect_account,
        sponsors_listing: @completed_transfer.sponsors_listing,
        primary_reference_id: "some other Stripe transfer")

      result = @completed_transfer.ledger_entries

      refute_includes result, ledger_entry
    end

    test "returns an empty list when transfer is not complete" do
      create(:payouts_ledger_entry, :transfer,
        stripe_connect_account: @incomplete_transfer.stripe_connect_account,
        sponsors_listing: @incomplete_transfer.sponsors_listing,
        primary_reference_id: @incomplete_transfer.stripe_transfer_id)
      assert_empty @incomplete_transfer.ledger_entries
    end

    test "returns an empty list when Stripe account does not exist" do
      @completed_transfer.stripe_connect_account.destroy!
      assert_empty @completed_transfer.reload.ledger_entries
    end
  end

  context "#reversible_amount_in_cents" do
    test "equal to the transfer amount_in_cents when no existing reversals" do
      assert_equal @completed_transfer.amount_in_cents, @completed_transfer.reversible_amount_in_cents
    end

    test "equal to the transfer amount minus the sum of the reversal amounts" do
      create_list(:invoiced_sponsorship_transfer_reversal, 2,
        invoiced_sponsorship_transfer: @completed_transfer,
        amount_in_cents: 1_00,
      )

      assert_equal @completed_transfer.amount_in_cents - 2_00, @completed_transfer.reversible_amount_in_cents
    end

    test "equal to zero when fully reversed" do
      create(:invoiced_sponsorship_transfer_reversal,
        invoiced_sponsorship_transfer: @completed_transfer,
        amount_in_cents: @completed_transfer.amount_in_cents,
      )

      assert_equal 0, @completed_transfer.reversible_amount_in_cents
    end

    test "equal to zero when not completed" do
      assert_equal 0, @incomplete_transfer.reversible_amount_in_cents
    end
  end

  context "not_fully_reversed scope" do
    test "omits transfer that had its total amount reversed" do
      create(:invoiced_sponsorship_transfer_reversal,
        invoiced_sponsorship_transfer: @completed_transfer,
        amount_in_cents: @completed_transfer.amount_in_cents,
      )
      refute_includes InvoicedSponsorshipTransfer.not_fully_reversed, @completed_transfer
    end

    test "includes transfer that has been partially reversed" do
      reversal = create(:invoiced_sponsorship_transfer_reversal,
        invoiced_sponsorship_transfer: @completed_transfer,
        amount_in_cents: 1_00,
      )
      assert_operator @completed_transfer.amount_in_cents, :>, reversal.amount_in_cents
      assert_includes InvoicedSponsorshipTransfer.not_fully_reversed, @completed_transfer
    end

    test "includes transfer that has no reversals" do
      assert_empty @completed_transfer.reversals, "need a transfer with no reversals"
      assert_includes InvoicedSponsorshipTransfer.not_fully_reversed, @completed_transfer
    end
  end

  context "#expires_at=" do
    test "can create a transfer without an expiration date" do
      transfer = create(:invoiced_sponsorship_transfer, expires_at: nil)

      assert_predicate transfer, :valid?
    end

    test "makes the transfer invalid if the given date is invalid" do
      transfer = build(:invoiced_sponsorship_transfer, expires_at: "invalid-date")

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:expires_at], "must be a valid date in the future"
    end

    test "makes the transfer invalid if the given date is today" do
      transfer = build(:invoiced_sponsorship_transfer, expires_at: Date.current.to_s)

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:expires_at], "must be a valid date in the future"
    end

    test "makes the transfer invalid if the given date is in the past" do
      transfer = build(:invoiced_sponsorship_transfer, expires_at: (Date.current - 1.day).to_s)

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:expires_at], "must be a valid date in the future"
    end

    test "makes the transfer valid if the given date is in the future" do
      transfer = create(:invoiced_sponsorship_transfer, expires_at: (Date.current + 1.day).to_s)

      assert_predicate transfer, :valid?
    end
  end

  context "#number_of_months=" do
    test "makes the transfer invalid if the number of months given is 0" do
      @completed_transfer.number_of_months = 0

      refute_predicate @completed_transfer, :valid?
      assert_includes @completed_transfer.errors[:number_of_months],
        "must be an integer greater than 0"
    end

    test "makes the transfer invalid if the number of months given is negative" do
      @completed_transfer.number_of_months = -1

      refute_predicate @completed_transfer, :valid?
      assert_includes @completed_transfer.errors[:number_of_months],
        "must be an integer greater than 0"
    end

    test "makes the transfer invalid if the number of months given is an invalid string" do
      @completed_transfer.number_of_months = "-1"

      refute_predicate @completed_transfer, :valid?
      assert_includes @completed_transfer.errors[:number_of_months],
        "must be an integer greater than 0"
    end

    test "accepts positive numbers given as strings" do
      @completed_transfer.number_of_months = "2"

      assert_predicate @completed_transfer, :valid?
      assert_equal 2, @completed_transfer.number_of_months
    end
  end

  context "#monthly_amount_in_cents" do
    test "returns the given amount when the number of months is not set" do
      assert_equal @completed_transfer.amount_in_cents, @completed_transfer.monthly_amount_in_cents
    end

    test "returns the given amount when the number of months is 1" do
      @completed_transfer.number_of_months = 1
      assert_equal @completed_transfer.amount_in_cents, @completed_transfer.monthly_amount_in_cents
    end

    test "returns the given amount when the number of months is 0" do
      @completed_transfer.number_of_months = 0
      assert_equal @completed_transfer.amount_in_cents, @completed_transfer.monthly_amount_in_cents
    end

    test "correctly divides the amount based on the number of months" do
      @completed_transfer.amount_in_dollars = 10_000
      @completed_transfer.number_of_months = 2
      assert_equal @completed_transfer.amount_in_cents / 2, @completed_transfer.monthly_amount_in_cents
    end

    test "correctly rounds down the amount based on the number of months" do
      @completed_transfer.amount_in_dollars = 10_000
      @completed_transfer.number_of_months = 3

      assert_equal 3_333_00, @completed_transfer.monthly_amount_in_cents
    end

    test "correctly rounds up the amount based on the number of months" do
      @completed_transfer.amount_in_dollars = 10_000
      @completed_transfer.number_of_months = 6

      assert_equal 1_667_00, @completed_transfer.monthly_amount_in_cents
    end
  end

  context "for_sponsor scope" do
    test "returns transfers associated to a specific sponsor" do
      result = InvoicedSponsorshipTransfer.for_sponsor(@completed_transfer.sponsor)

      assert_includes result, @completed_transfer
    end

    test "does not include transfers associated to different sponsors" do
      result = InvoicedSponsorshipTransfer.for_sponsor(@completed_transfer.sponsor)

      refute_includes result, @incomplete_transfer
    end
  end

  context "created_between scope" do
    test "includes transfers created between the given time range" do
      start_date = @completed_transfer.created_at - 1.month
      end_date = @completed_transfer.created_at + 1.month

      result = InvoicedSponsorshipTransfer.created_between(start_date, end_date)

      assert_includes result, @completed_transfer
    end
  end
end
