# typed: true
# frozen_string_literal: true

require "stripe"

class SetupStripeConnectAccountJob < ModifyStripeConnectAccountJob
  queue_as :stripe

  locked_by timeout: 10.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  RETRYABLE_ERRORS = [
    Stripe::APIConnectionError,
    Stripe::StripeError,
  ].freeze

  retry_on(*RETRYABLE_ERRORS) do |job, error|
    Failbot.report(error,
      sponsors_listing_id: job.arguments.first.id,
      app: "github-external-request",
    )
  end

  sig { params(sponsors_listing: SponsorsListing, existing_stripe_account: Billing::StripeConnect::Account).void }
  def perform(sponsors_listing, existing_stripe_account:)
    return unless GitHub.sponsors_enabled?
    existing_stripe_account.with_lock do
      with_write { Sponsors::SyncStripeAccountDetails.call(existing_stripe_account) }
    end
  end
end
