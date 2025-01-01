# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class InvoicedSponsorshipTransferReversalJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @transfer_record = create(:invoiced_sponsorship_transfer, :completed)
    @reversal_record = create(:invoiced_sponsorship_transfer_reversal,
      invoiced_sponsorship_transfer: @transfer_record)
    @stripe_transfer_id = "tr_1HjX2REQsq43iHhXDI2LsOE3"
    @reversal_record.invoiced_sponsorship_transfer.update!(stripe_transfer_id: @stripe_transfer_id)
  end

  if GitHub.sponsors_enabled?
    test "creates a new Stripe transfer reversal and updates the InvoicedSponsorshipTransferReversal record" do
      assert_nil @reversal_record.stripe_transfer_reversal_id
      assert_nil @reversal_record.transfer_reversal_created_at

      fake_reversal_id = "trr_1HllIbEQsq43iHhXGRFfFoWt"
      fake_reversal_time = 1604970329
      fake_response = stub(id: fake_reversal_id, created: fake_reversal_time)
      Stripe::Transfer.expects(:create_reversal).once.with(
        @stripe_transfer_id,
        amount: @reversal_record.amount_in_cents,
        metadata: {
          payment_amount_reversed: @reversal_record.amount_in_cents,
          match_amount_reversed: 0,
          invoiced_sponsorship_transfer_reversal: @reversal_record.id,
          actor_id: @reversal_record.actor_id,
          sponsors_listing_id: @transfer_record.sponsors_listing_id,
        }
      ).returns(fake_response)

      InvoicedSponsorshipTransferReversalJob.perform_now(@reversal_record)

      @reversal_record.reload
      assert_equal fake_reversal_id, @reversal_record.stripe_transfer_reversal_id
      assert_equal Time.at(fake_reversal_time), @reversal_record.transfer_reversal_created_at
    end

    test "no-op if the InvoicedSponsorshipTransferReversal record already has Stripe transfer reversal details" do
      stripe_transfer_reversal_id = "trr_000000000"
      transfer_reversal_created_at = Time.parse("2020-11-02T12:00:00Z")
      @reversal_record.update!(
        stripe_transfer_reversal_id: stripe_transfer_reversal_id,
        transfer_reversal_created_at: transfer_reversal_created_at
      )

      Stripe::Transfer.expects(:create_reversal).never

      InvoicedSponsorshipTransferReversalJob.perform_now(@reversal_record)

      @reversal_record.reload
      assert_equal stripe_transfer_reversal_id, @reversal_record.stripe_transfer_reversal_id
      assert_equal transfer_reversal_created_at, @reversal_record.transfer_reversal_created_at
    end

    test "reports an error if Stripe transfer is not found" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @reversal_record.invoiced_sponsorship_transfer.update!(stripe_transfer_id: "tr_NOT_A_REAL_ID")

      VCR.use_cassette("stripe/invoiced_sponsorship_transfer_reversal_transfer_not_found") do
        InvoicedSponsorshipTransferReversalJob.perform_now(@reversal_record)
      end

      @reversal_record.reload
      assert_nil @reversal_record.stripe_transfer_reversal_id
      assert_nil @reversal_record.transfer_reversal_created_at

      increments = GitHub.dogstats.increments("stripe.transfer_reversal.failed")
      assert_equal 1, increments.count
    end

    test "retries on dirty exit" do
      assert_retry_on_dirty_exit job: InvoicedSponsorshipTransferReversalJob, args: [@reversal_record]
    end

    test "retries on Stripe::APIConnectionError" do
      Stripe::Transfer.stubs(:create_reversal).raises(Stripe::APIConnectionError)
      InvoicedSponsorshipTransferReversalJob.any_instance.expects(:retry_job).once
      InvoicedSponsorshipTransferReversalJob.perform_now(@reversal_record)
    end

    test "retries on Stripe::StripeError" do
      Stripe::Transfer.stubs(:create_reversal).raises(Stripe::StripeError)
      InvoicedSponsorshipTransferReversalJob.any_instance.expects(:retry_job).once
      InvoicedSponsorshipTransferReversalJob.perform_now(@reversal_record)
    end

    test "uses the expected lock_key" do
      job = InvoicedSponsorshipTransferReversalJob.new
      assert_equal ActiveJob::LockingJob::DEFAULT_LOCK_KEY, job.lock_key
    end
  else
    test "no-op in enterprise" do
      assert_nil @reversal_record.stripe_transfer_reversal_id
      assert_nil @reversal_record.transfer_reversal_created_at

      Stripe::Transfer.expects(:create_reversal).never

      InvoicedSponsorshipTransferReversalJob.perform_now(@reversal_record)

      @reversal_record.reload
      assert_nil @reversal_record.stripe_transfer_reversal_id
      assert_nil @reversal_record.transfer_reversal_created_at
    end
  end
end
