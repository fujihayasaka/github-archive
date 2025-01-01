# typed: true
# frozen_string_literal: true

class SyncSponsorsStripeAccountJob < ModifyStripeConnectAccountJob
  queue_as :sponsors_stripe_sync
  retry_on_dirty_exit

  discard_on ActiveRecord::RecordNotFound

  TIMEOUT_IN_HOURS = 1
  locked_by timeout: TIMEOUT_IN_HOURS.hours, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  RETRYABLE_ERRORS = [
    Stripe::APIConnectionError,
    Stripe::StripeError,
    Stripe::PermissionError,
    ActiveRecord::RecordInvalid,
    Billing::StripeConnect::Account::SyncError,
  ].freeze
  retry_on(*RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 5) do |job, error|
    stripe_account = job.arguments.first
    Failbot.report(error,
      stripe_connect_account_id: stripe_account.id,
      sponsors_listing_id: stripe_account.sponsors_listing_id,
      stripe_account_id: stripe_account.stripe_account_id,
      user_id: stripe_account.sponsorable_id,
      app: "github-external-request",
    )
  end

  sig { params(stripe_account: T.nilable(Billing::StripeConnect::Account)).void }
  def perform(stripe_account)
    return unless stripe_account && GitHub.sponsors_enabled?

    sponsors_listing = stripe_account.sponsors_listing
    return unless sponsors_listing

    ActiveRecord::Base.connected_to(role: :writing) do
      stripe_account.with_lock { Sponsors::SyncStripeAccountDetails.call(stripe_account) }
    end
  end
end
