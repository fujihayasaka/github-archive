# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::TransferMatchReversalTestCase < GitHub::BillingTestCase
  fixtures do
    @stripe_account = create(:stripe_connect_account, stripe_account_id: "acct_1Ep35IFxJZYbadPl")
    @stripe_transfer_id = "tr_1G60MTEQsq43iHhXoIM7Ppjx"
  end

  test "creates a match reversal" do
    VCR.use_cassette("stripe/reverse_transfer_match") do
      initial_count = ::Stripe::Transfer.retrieve(@stripe_transfer_id).reversals.count

      Billing::Stripe::TransferMatchReversal.perform(
        stripe_account: @stripe_account,
        transfer_id: @stripe_transfer_id,
        match_amount_to_reverse: ::Billing::Money.parse("$1.00")
      )

      reversals = ::Stripe::Transfer.retrieve(@stripe_transfer_id).reversals
      newest_reversal = reversals.data.first

      assert_equal initial_count + 1, reversals.count
      assert_equal 1_00, newest_reversal.amount
      assert_equal "0", newest_reversal.metadata.payment_amount_reversed
      assert_equal "100", newest_reversal.metadata.match_amount_reversed
    end
  end

  test "raises a NotEnoughRemainingMatchError if requested match reversal is more than remains" do
    VCR.use_cassette("stripe/reverse_transfer_match") do
      assert_raises ::Billing::Stripe::TransferMatchReversal::NotEnoughRemainingMatchError do
        Billing::Stripe::TransferMatchReversal.perform(
          stripe_account: @stripe_account,
          transfer_id: @stripe_transfer_id,
          # This transfer originally had a $50 match
          match_amount_to_reverse: ::Billing::Money.parse("$55.00")
        )
      end
    end
  end

  test "raises a DestinationMismatchError if stripe account does not match transfer" do
    VCR.use_cassette("stripe/reverse_transfer_match") do
      assert_raises ::Billing::Stripe::TransferMatchReversal::DestinationMismatchError do
        Billing::Stripe::TransferMatchReversal.perform(
          stripe_account: create(:stripe_connect_account),
          transfer_id: @stripe_transfer_id,
          match_amount_to_reverse: ::Billing::Money.parse("$1.00")
        )
      end
    end
  end

  test "raises a AlreadyPaidOutError if transfer occurred before last payout" do
    # the timestamp is from the `reverse_transfer_match` VCR cassette
    transfer_created_at = Time.at(1580242117).to_datetime
    create(:stripe_webhook, kind: :payout_created,
      payload: {
        data: { object: { created: (transfer_created_at + 2.days).to_i } },
        account: @stripe_account.stripe_account_id,
      })

    VCR.use_cassette("stripe/reverse_transfer_match") do
      assert_raises ::Billing::Stripe::TransferMatchReversal::AlreadyPaidOutError do
        Billing::Stripe::TransferMatchReversal.perform(
          stripe_account: @stripe_account,
          transfer_id: @stripe_transfer_id,
          match_amount_to_reverse: ::Billing::Money.parse("$1.00")
        )
      end
    end
  end
end
