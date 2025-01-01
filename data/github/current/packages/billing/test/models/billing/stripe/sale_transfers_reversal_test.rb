# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::SaleTransfersReversalTestCase < GitHub::BillingTestCase
  test "creates a reversal" do
    VCR.use_cassette("zuora/stripe/reverse_transfer") do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      stripe_transfer_id = "tr_1FA0hMEQsq43iHhXb97AdND2"
      zuora_transaction_id = "2c92c0fb6c99c25e016cb5ec29103370"
      stripe_refund_id = "re_#{SecureRandom.hex(8)}"
      zuora_refund_id = SecureRandom.hex(16)

      ::Stripe::Transfer.expects(:create_reversal).with do |id, params|
        assert_equal stripe_transfer_id, id

        assert_equal 10_00, params[:amount]

        metadata = params[:metadata]
        assert_equal 5_00, metadata[:payment_amount_reversed]
        assert_equal 5_00, metadata[:match_amount_reversed]
        assert_equal stripe_refund_id, metadata[:stripe_refund_id]
        assert_equal zuora_refund_id, metadata[:zuora_refund_id]
      end

      Billing::Stripe::SaleTransfersReversal.perform(
        sale_transaction_id: zuora_transaction_id,
        stripe_refund_id: stripe_refund_id,
        zuora_refund_id: zuora_refund_id,
      )

      transfer_reversal_failed = GitHub.dogstats.increments("stripe.transfer_reversal.failed")

      # If there were no errors, we assume success
      assert_equal 0, transfer_reversal_failed.count
    end
  end

  test "creates a partial reversal" do
    # Note that partial reversals must be invoked manually from a Rails console;
    # they do not happen automatically in the event of a partial refund!
    VCR.use_cassette("zuora/stripe/reverse_transfer") do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      stripe_transfer_id = "tr_1FA0hMEQsq43iHhXb97AdND2"
      zuora_transaction_id = "2c92c0fb6c99c25e016cb5ec29103370"
      stripe_refund_id = "re_#{SecureRandom.hex(8)}"
      zuora_refund_id = SecureRandom.hex(16)

      ::Stripe::Transfer.expects(:create_reversal).with do |id, params|
        assert_equal stripe_transfer_id, id

        assert_equal 2_00, params[:amount]

        metadata = params[:metadata]
        assert_equal 1_00, metadata[:payment_amount_reversed]
        assert_equal 1_00, metadata[:match_amount_reversed]
        assert_equal stripe_refund_id, metadata[:stripe_refund_id]
        assert_equal zuora_refund_id, metadata[:zuora_refund_id]
      end

      Billing::Stripe::SaleTransfersReversal.perform(
        sale_transaction_id: zuora_transaction_id,
        stripe_refund_id: stripe_refund_id,
        zuora_refund_id: zuora_refund_id,
        payment_amount_to_reverse: 1_00,
        match_amount_to_reverse: 1_00,
      )

      transfer_reversal_failed = GitHub.dogstats.increments("stripe.transfer_reversal.failed")

      # If there were no errors, we assume success
      assert_equal 0, transfer_reversal_failed.count
    end
  end

  test "raises and logs if it cannot find transfer" do
    VCR.use_cassette("zuora/stripe/transfer_not_found") do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      zuora_transaction_id = "this_does_not_exist"
      stripe_refund_id = "re_#{SecureRandom.hex(8)}"
      zuora_refund_id = SecureRandom.hex(16)

      assert_raises Billing::Stripe::SaleTransfersReversal::TransferNotFound do
        Billing::Stripe::SaleTransfersReversal.perform(
          sale_transaction_id: zuora_transaction_id,
          stripe_refund_id: stripe_refund_id,
          zuora_refund_id: zuora_refund_id,
        )
      end

      increments = GitHub.dogstats.increments("stripe.transfer_reversal.failed")

      assert_equal 1, increments.count
    end
  end

  test "raises and logs if no zuora_transaction_id is given" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    ::Stripe::Transfer.expects(:list).never

    assert_raises Billing::Stripe::SaleTransfersReversal::TransferNotFound do
      # Params similar to what we'd see in the transfer_match_reversals_controller
      Billing::Stripe::SaleTransfersReversal.perform(
        sale_transaction_id: nil,
        stripe_refund_id: nil,
        zuora_refund_id: nil,
        payment_amount_to_reverse: 0,
        match_amount_to_reverse: 100,
      )
    end

    increments = GitHub.dogstats.increments("stripe.transfer_reversal.failed")
    assert_equal 1, increments.count
  end

  test "does not blow up if transfer is already reversed" do
    VCR.use_cassette("zuora/stripe/reverse_transfer") do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      zuora_transaction_id = "2c92c0fb6b8e0598016b91ab98b14a21"
      stripe_refund_id = "re_#{SecureRandom.hex(8)}"
      zuora_refund_id = SecureRandom.hex(16)

      Billing::Stripe::SaleTransfersReversal.perform(
        sale_transaction_id: zuora_transaction_id,
        stripe_refund_id: stripe_refund_id,
        zuora_refund_id: zuora_refund_id,
      )

      Billing::Stripe::SaleTransfersReversal.perform(
        sale_transaction_id: zuora_transaction_id,
        stripe_refund_id: stripe_refund_id,
        zuora_refund_id: zuora_refund_id,
      )

      transfer_reversal_failed = GitHub.dogstats.increments("stripe.transfer_reversal.failed")

      # If there were no errors, we assume success
      assert_equal 0, transfer_reversal_failed.count
    end
  end
end
