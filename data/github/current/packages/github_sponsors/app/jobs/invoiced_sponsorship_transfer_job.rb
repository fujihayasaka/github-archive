# typed: true
# frozen_string_literal: true

# Public: Mark an invoiced sponsorship as paid and record details of the Stripe transfer (from GitHub's Stripe account
# to the sponsorable's Stripe account) on the invoiced transfer record. Only runs after GitHub staff has
# manually confirmed the invoice has been paid.
class InvoicedSponsorshipTransferJob < ApplicationJob
  queue_as :stripe

  retry_on_dirty_exit

  locked_by timeout: 10.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  RETRYABLE_ERRORS = [
    Stripe::APIConnectionError,
    Stripe::StripeError,
  ].freeze

  retry_on(*RETRYABLE_ERRORS) do |job, error|
    invoiced_sponsorship_transfer = job.arguments.first
    Failbot.report(error,
      invoiced_sponsorship_transfer_id: invoiced_sponsorship_transfer.id,
      app: "github-external-request",
    )
  end

  attr_reader :transfer_record, :stripe_transfer

  def perform(invoiced_sponsorship_transfer)
    @transfer_record = invoiced_sponsorship_transfer
    return unless GitHub.sponsors_enabled?
    return if transfer_record.completed?

    if create_stripe_transfer
      InvoicedSponsorshipTransfer.throttle_writes_with_retry do # ballast cluster
        Sponsorship.throttle_writes_with_retry do # collab cluster
          transfer_record.record_stripe_transfer( # writes to ballast and collab clusters
            transfer_id: stripe_transfer.id,
            time: Time.at(stripe_transfer.created),
          )
        end
      end
    end
  end

  private

  def create_stripe_transfer
    @stripe_transfer = Stripe::Transfer.create(
      amount: transfer_record.amount_in_cents,
      currency: "usd",
      destination: transfer_record.stripe_account_id,
      transfer_group: transfer_record.zuora_payment_id,
      metadata: {
        payment_amount: transfer_record.amount_in_cents,
        match_amount: 0,
        invoiced_sponsorship_transfer_id: transfer_record.id,
        sponsor_id: transfer_record.sponsor_id,
        actor_id: transfer_record.actor_id,
        sponsors_listing_id: transfer_record.sponsors_listing_id,
      }
    )
  rescue Stripe::InvalidRequestError => e
    GitHub.dogstats.increment("stripe.transfer.failed")
    Failbot.report(e)
    false
  rescue Stripe::PermissionError => e
    GitHub.dogstats.increment("stripe.permission_error", tags: ["action:transfer"])
    Failbot.report(e)
    false
  end
end
