# typed: true
# frozen_string_literal: true

require "stripe"

class ConfigureStripeAccountJob < ModifyStripeConnectAccountJob
  queue_as :stripe

  locked_by timeout: 10.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  RETRYABLE_ERRORS = [
    Stripe::APIConnectionError,
    Stripe::StripeError,
    Sponsors::ConfigureStripeAccount::UpdatePayoutsFailedError,
  ].freeze

  DISCARDABLE_ERRORS = [
    Stripe::PermissionError,
    Stripe::OAuth::InvalidGrantError,
    Stripe::InvalidRequestError,
  ].freeze

  retry_on(*RETRYABLE_ERRORS) do |job, error|
    stripe_account, named_args = job.arguments
    Failbot.report(error,
      stripe_connect_account_id: stripe_account.id,
      stripe_account_id: stripe_account.stripe_account_id,
      freeze_payouts: named_args[:freeze_payouts],
      actor_id: named_args[:actor]&.id,
      app: "github-external-request",
    )
  end

  discard_on(*DISCARDABLE_ERRORS) do |job, error|
    stripe_account, named_args = job.arguments
    Failbot.report(error,
      stripe_connect_account_id: stripe_account.id,
      stripe_account_id: stripe_account.stripe_account_id,
      freeze_payouts: named_args[:freeze_payouts],
      actor_id: named_args[:actor]&.id,
      app: "github-external-request",
    )

    if error.is_a?(Stripe::PermissionError)
      GitHub.dogstats.increment("stripe.permission_error", tags: ["action:toggle_payouts"])
    end
  end

  sig do
    params(
      stripe_account: Billing::StripeConnect::Account,
      freeze_payouts: T::Boolean,
      actor: T.nilable(User),
      reason: T.nilable(String)
    ).void
  end
  def perform(stripe_account, freeze_payouts: false, actor: nil, reason: nil)
    return unless GitHub.sponsors_enabled?

    Failbot.push({
      stripe_connect_account_id: stripe_account.id,
      stripe_account_id: stripe_account.stripe_account_id,
      actor_id: actor&.id,
      freeze_payouts: freeze_payouts,
    })

    with_write do
      stripe_account.with_lock do
        Sponsors::ConfigureStripeAccount.call(
          account: stripe_account,
          freeze_payouts: freeze_payouts,
          actor: actor,
          reason: reason,
        )
      end
    end
  end
end
