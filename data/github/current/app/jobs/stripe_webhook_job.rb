# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class StripeWebhookJob < ApplicationJob
  RETRYABLE_ERRORS = [
    Errno::ECONNRESET,
    Faraday::ConnectionFailed,
    Faraday::SSLError,
    Faraday::TimeoutError,
    Net::OpenTimeout,
    WaitForReplication::DataUnavailable
  ].freeze

  discard_on(StandardError) do |job, error|
    GitHub.dogstats.increment(
      "stripe.webhook_error",
      tags: ["kind:#{job.webhook_kind}", "exception:#{error.class.name.parameterize}"],
    )
    Failbot.report(error)
  end

  RETRYABLE_ERRORS.each do |error_class|
    retry_on(error_class, wait: :polynomially_longer) do |_, error|
      Failbot.report(error)
    end
  end

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  queue_as :stripe

  attr_reader :webhook_kind

  # Public: Perform the job
  #
  # stripe_webhook - The Billing::StripeWebhook model to handle
  #
  # Returns nothing
  def perform(stripe_webhook)
    @webhook_kind = stripe_webhook.kind

    latency_ms = (Time.now.to_f - stripe_webhook.created_at.to_f) * 1_000
    GitHub.dogstats.timing("stripe.webhook_latency", latency_ms.to_i)

    with_write do
      stripe_webhook.perform
    end
  end
end
