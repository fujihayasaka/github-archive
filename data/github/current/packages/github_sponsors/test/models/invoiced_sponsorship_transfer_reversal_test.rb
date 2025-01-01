# typed: true
# frozen_string_literal: true

require "test_helper"

class InvoicedSponsorshipTransferReversalTest < GitHub::TestCase
  context "#completed?" do
    test "returns true if the Stripe transfer reversal ID is present" do
      reversal = InvoicedSponsorshipTransferReversal.new(stripe_transfer_reversal_id: "trr_123")
      assert_predicate reversal, :completed?
    end

    test "returns false if the Stripe transfer reversal ID is blank" do
      reversal = InvoicedSponsorshipTransferReversal.new(stripe_transfer_reversal_id: nil)
      refute_predicate reversal, :completed?
    end
  end
end
