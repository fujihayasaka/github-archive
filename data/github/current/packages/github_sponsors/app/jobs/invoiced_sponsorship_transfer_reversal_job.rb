# typed: true
# frozen_string_literal: true

class InvoicedSponsorshipTransferReversalJob < ApplicationJob
  queue_as :stripe

  retry_on_dirty_exit

  locked_by timeout: 10.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  RETRYABLE_ERRORS = [
    Stripe::APIConnectionError,
    Stripe::StripeError,
  ].freeze

  retry_on(*RETRYABLE_ERRORS) do |job, error|
    invoiced_sponsorship_transfer_reversal = job.arguments.first
    Failbot.report(error,
      invoiced_sponsorship_transfer_reversal_id: invoiced_sponsorship_transfer_reversal.id,
      app: "github-external-request",
    )
  end

  attr_reader :reversal_record, :stripe_transfer_reversal

  def perform(invoiced_sponsorship_transfer_reversal)
    @reversal_record = invoiced_sponsorship_transfer_reversal
    return unless GitHub.sponsors_enabled?
    return if reversal_record.completed?

    if create_stripe_transfer_reversal
      InvoicedSponsorshipTransferReversal.throttle_writes_with_retry do
        reversal_record.update!(
          stripe_transfer_reversal_id: stripe_transfer_reversal.id,
          transfer_reversal_created_at: Time.at(stripe_transfer_reversal.created),
        )
      end
    end
  end

  private

  def create_stripe_transfer_reversal
    @stripe_transfer_reversal = Stripe::Transfer.create_reversal(
      reversal_record.stripe_transfer_id,
      amount: reversal_record.amount_in_cents,
      metadata: {
        payment_amount_reversed: reversal_record.amount_in_cents,
        match_amount_reversed: 0,
        # Metadata keys must be under 40 characters, so `id` is omitted below
        invoiced_sponsorship_transfer_reversal: reversal_record.id,
        actor_id: reversal_record.actor_id,
        sponsors_listing_id: reversal_record.sponsors_listing_id,
      }
    )
  rescue Stripe::InvalidRequestError => e
    GitHub.dogstats.increment("stripe.transfer_reversal.failed")
    Failbot.report(e)
    false
  rescue Stripe::PermissionError => e
    GitHub.dogstats.increment("stripe.permission_error", tags: ["action:transfer_reversal"])
    Failbot.report(e)
    false
  end
end
