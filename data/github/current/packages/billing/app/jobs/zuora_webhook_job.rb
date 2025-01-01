# typed: strict
# frozen_string_literal: true

class ZuoraWebhookJob < ApplicationJob
  include GitHub::Memoizer
  include GitHub::Billing::ZuoraRateLimitHandler
  queue_as :zuora

  DEFAULT_CONCURRENCY_LIMIT = 100
  PAYMENT_TYPE_WEBHOOK_CONCURRENCY_LIMIT = 50
  MAX_RETRIES = 25

  RETRYABLE_ERRORS = T.let(::Billing::Zuora::RETRYABLE_ERRORS + [
    ::Billing::Zuora::LockCompetitionError,
    ::Billing::ZuoraWebhook::RetryableError,
    Audit::EventForwarder::SubscribeError,
    Braintree::UnexpectedError,
    Stripe::APIError,
    WaitForReplication::DataUnavailable
  ].freeze, T::Array[T.class_of(StandardError)])

  discard_on(StandardError) do |job, error|
    GitHub.dogstats.increment(
      "zuora.webhook_error",
      tags: ["category:#{job.type}",
             "exception:#{error.class.name.parameterize}"],
    )
    Failbot.report(error)
  end

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  RETRYABLE_ERRORS.each do |retryable|
    retry_on(retryable, wait: :polynomially_longer) do |job, error|
      GitHub.dogstats.increment(
        "zuora.webhook_error",
        tags: ["category:#{job.type}",
               "exception:#{error.class.name.parameterize}"],
      )
      Failbot.report(error)
    end
  end

  resolve_tenant_context do |zuora_webhook|
    zuora_webhook.customer&.billable_owner
  end

  sig { returns(T::Boolean) }
  def self.inside_invoice_or_payment_run_hours?
    now = GitHub::Billing.timezone.now
    # Invoice run currently starts at 1am PT and takes between 2 to 5 hours to complete.
    # We receive invoice posted webhooks for about 15-30 minutes after it ends.
    invoice_run_start = now.change(hour: 3)
    invoice_run_end = now.change(hour: 6, min: 30)

    # Payment run currently starts at 9am PT and takes between 2 to 4 hours to complete.
    payment_run_start = now.change(hour: 9, min: 30)
    payment_run_end = now.change(hour: 13, min: 30)

    (invoice_run_start..invoice_run_end).cover?(now) || (payment_run_start..payment_run_end).cover?(now)
  end

  sig { params(executions: Integer).returns(T.any(Float, Integer)) }
  def self.restraint_lock_wait_delay(executions)
    dd_tags = []
    jitter = 0.5

    delay =
      if inside_invoice_or_payment_run_hours?
        dd_tags << "peak_time:true"
        3.minutes.to_i
      else
        dd_tags << "peak_time:false"
        1.minute.to_i
      end
    # Peak times
    wait_delay = delay + (Kernel.rand * delay * rand(-jitter..jitter))

    GitHub.dogstats.distribution("zuora.webhook_job.restraint_lock_wait_delay", wait_delay, tags: dd_tags)

    wait_delay
  end

  retry_on(GitHub::Restraint::UnableToLock, wait: ->(executions) {
    T.bind(self, T.class_of(ZuoraWebhookJob))
    restraint_lock_wait_delay(executions)
  }, attempts: MAX_RETRIES) do |job, error|
    GitHub.dogstats.increment(
      "zuora.webhook_error",
      tags: ["category:#{job.type}",
             "exception:#{error.class.name.parameterize}"],
    )

    Failbot.report(error)
  end

  retry_on(ActiveRecord::RecordNotUnique, wait: 1.minute, attempts: 4) do |_job, error|
    Failbot.report(error)
  end

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, ZuoraWebhookJob)

    zuora_rate_limit_handler(self, error)
  end

  sig { returns(T.nilable(String)) }
  attr_reader :type

  sig { params(zuora_webhook: Billing::ZuoraWebhook).void }
  def perform(zuora_webhook)
    return if zuora_webhook.processed?

    @type = T.let(zuora_webhook.kind, T.nilable(String))

    Failbot.push("gh.billing.zuora.webhook_type": type, "gh.billing.zuora.webhook_id": zuora_webhook.id)
    tags = [
      "category:#{type}",
      "status:#{zuora_webhook.status}",
      "concurrency:#{concurrency_limit}",
    ]
    GitHub.dogstats.distribution_time("zuora.webhook_job.perform_time", tags: tags) do
      Failbot.push("gh.billing.zuora.webhook_job.concurrency_limit": concurrency_limit)
      concurrent_restraint = GitHub::Restraint.new
      concurrent_restraint.lock!("ZuoraWebhookJobPerform", concurrency_limit, 5.minutes) do
        with_write do
          zuora_webhook.perform
        end
      end
    end
  end

  sig { params(webhook_type: String, concurrency: Integer).void }
  def self.set_concurrency(webhook_type:, concurrency:)
    Billing::Kv.store.set("zuora_webhook_job:#{webhook_type}:concurrency", concurrency.to_s)
  end

  private

  sig { returns(T::Boolean) }
  def payment_webhook?
    type == "payment_processed" || type == "payment_declined"
  end

  sig { returns(Integer) }
  memoize def concurrency_limit
    return PAYMENT_TYPE_WEBHOOK_CONCURRENCY_LIMIT if payment_webhook?

    (
      Billing::Kv.store.get("zuora_webhook_job:#{type}:concurrency").value { DEFAULT_CONCURRENCY_LIMIT } ||
      DEFAULT_CONCURRENCY_LIMIT
    ).to_i
  end

end
