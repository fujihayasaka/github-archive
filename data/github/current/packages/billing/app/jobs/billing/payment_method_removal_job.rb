# typed: strict
# frozen_string_literal: true

class Billing::PaymentMethodRemovalJob < BillingJob
  include GitHub::Billing::ZuoraRateLimitHandler

  Billing::Zuora::RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer, attempts: 5) do |_job, error|
      Failbot.report(error)
    end
  end

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, Billing::PaymentMethodRemovalJob)

    zuora_rate_limit_handler(self, error)
  end

  retry_on GitHub::Restraint::UnableToLock, wait: 1.minute, attempts: 5 do |_job, error|
    Failbot.report(error)
  end

  sig { params(user: User, actor: User).void }
  def perform(user:, actor:)
    with_write do
      lock!(user) do
        user.remove_all_payment_methods(actor) if user.payment_method&.valid_payment_token?
      end
    end
  end

  private

  sig { params(user: User, block: T.proc.returns(T.untyped)).returns(T.untyped) }
  def lock!(user, &block)
    lock_key = "payment-method-removal-job-#{user.id}"

    restraint.lock!(lock_key, _max_concurrency = 1, _ttl = 5.minutes) do
      yield
    end
  end

  sig { returns(GitHub::Restraint) }
  def restraint
    @restraint ||= T.let(GitHub::Restraint.new, T.nilable(GitHub::Restraint))
  end
end
