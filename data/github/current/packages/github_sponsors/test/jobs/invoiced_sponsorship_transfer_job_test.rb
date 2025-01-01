# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class InvoicedSponsorshipTransferJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @sponsors_listing = create(:sponsors_listing, :approved, :with_stripe_account)
    @stripe_account_id = "acct_1Ep35IFxJZYbadPl"
    @sponsors_listing.active_stripe_connect_account.update!(stripe_account_id: @stripe_account_id)
    @transfer_record = create(:invoiced_sponsorship_transfer, sponsors_listing: @sponsors_listing)
    @sponsorship = create(:sponsorship, :invoiced, invoiced_sponsorship_transfer: @transfer_record)
  end

  if GitHub.sponsors_enabled?
    test "creates a new Stripe transfer, updates the InvoicedSponsorshipTransfer, and updates the Sponsorship" do
      assert_nil @transfer_record.stripe_transfer_id
      assert_nil @transfer_record.transfer_created_at
      assert_nil @sponsorship.paid_at

      fake_transfer_id = "tr_1HjX2REQsq43iHhXDI2LsOE3"
      fake_transfer_time = 1604438855
      fake_transfer = stub(id: fake_transfer_id, created: fake_transfer_time)
      Stripe::Transfer.expects(:create).once.with(
        amount: @transfer_record.amount_in_cents,
        currency: "usd",
        destination: @stripe_account_id,
        transfer_group: @transfer_record.zuora_payment_id,
        metadata: {
          payment_amount: @transfer_record.amount_in_cents,
          match_amount: 0,
          invoiced_sponsorship_transfer_id: @transfer_record.id,
          sponsor_id: @transfer_record.sponsor_id,
          actor_id: @transfer_record.actor_id,
          sponsors_listing_id: @sponsors_listing.id,
        }
      ).returns(fake_transfer)

      InvoicedSponsorshipTransferJob.perform_now(@transfer_record)

      @transfer_record.reload
      assert_equal fake_transfer_id, @transfer_record.stripe_transfer_id
      assert_equal Time.at(fake_transfer_time), @transfer_record.transfer_created_at
      assert_equal Time.at(fake_transfer_time), @sponsorship.reload.paid_at
    end

    test "no-op if the InvoicedSponsorshipTransfer record already has Stripe transfer details" do
      stripe_transfer_id = "tr_000000000"
      transfer_created_at = Time.parse("2020-11-01T12:00:00Z")
      @transfer_record.update!(
        stripe_transfer_id: stripe_transfer_id,
        transfer_created_at: transfer_created_at
      )
      @sponsorship.update!(paid_at: transfer_created_at)

      Stripe::Transfer.expects(:create).never

      InvoicedSponsorshipTransferJob.perform_now(@transfer_record)

      @transfer_record.reload
      assert_equal stripe_transfer_id, @transfer_record.stripe_transfer_id
      assert_equal transfer_created_at, @transfer_record.transfer_created_at
      assert_equal transfer_created_at, @sponsorship.paid_at
    end

    test "reports an error if Stripe Connect account is not found" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @transfer_record.stripe_connect_account.update!(stripe_account_id: "no_account")

      VCR.use_cassette("zuora/stripe/connect_account_not_found") do
        InvoicedSponsorshipTransferJob.perform_now(@transfer_record)
      end

      @transfer_record.reload
      assert_nil @transfer_record.stripe_transfer_id
      assert_nil @transfer_record.transfer_created_at
      assert_nil @sponsorship.reload.paid_at

      increments = GitHub.dogstats.increments("stripe.transfer.failed")
      assert_equal 1, increments.count
    end

    test "retries on dirty exit" do
      assert_retry_on_dirty_exit job: InvoicedSponsorshipTransferJob, args: [@transfer_record]
    end

    test "retries on Stripe::APIConnectionError" do
      Stripe::Transfer.stubs(:create).raises(Stripe::APIConnectionError)
      InvoicedSponsorshipTransferJob.any_instance.expects(:retry_job).once
      InvoicedSponsorshipTransferJob.perform_now(@transfer_record)
    end

    test "retries on Stripe::StripeError" do
      Stripe::Transfer.stubs(:create).raises(Stripe::StripeError)
      InvoicedSponsorshipTransferJob.any_instance.expects(:retry_job).once
      InvoicedSponsorshipTransferJob.perform_now(@transfer_record)
    end

    test "uses the expected lock_key" do
      job = InvoicedSponsorshipTransferJob.new
      assert_equal ActiveJob::LockingJob::DEFAULT_LOCK_KEY, job.lock_key
    end
  else
    test "no-op in enterprise" do
      assert_nil @transfer_record.stripe_transfer_id
      assert_nil @transfer_record.transfer_created_at
      assert_nil @sponsorship.paid_at

      Stripe::Transfer.expects(:create).never

      InvoicedSponsorshipTransferJob.perform_now(@transfer_record)

      @transfer_record.reload
      assert_nil @transfer_record.stripe_transfer_id
      assert_nil @transfer_record.transfer_created_at
      assert_nil @sponsorship.reload.paid_at
    end
  end
end
