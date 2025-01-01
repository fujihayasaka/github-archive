# typed: true
# frozen_string_literal: true

class ModifyStripeConnectAccountJob < ApplicationJob
  extend T::Helpers
  extend T::Sig

  abstract!

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  LOCK_CONFLICT_ATTEMPTS = 10

  retry_on(GitHub::Restraint::UnableToLock,
    wait: :polynomially_longer,
    attempts: LOCK_CONFLICT_ATTEMPTS,
  ) do |job, error|
    args = job.arguments
    stripe_account = args.detect { |arg| arg.is_a?(Billing::StripeConnect::Account) }
    stripe_account ||= args
      .detect { |arg| arg.is_a?(Hash) && arg.values.any? { |value| value.is_a?(Billing::StripeConnect::Account) } }
      &.values
      &.detect { |arg| arg.is_a?(Billing::StripeConnect::Account) }
    if stripe_account
      Failbot.push(stripe_connect_account_id: stripe_account.id, stripe_account_id: stripe_account.stripe_account_id)
    end
    Failbot.report(error, app: "github-non-user-facing")
  end
end
