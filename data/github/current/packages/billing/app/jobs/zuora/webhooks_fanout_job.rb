# typed: strict
# frozen_string_literal: true

class Zuora::WebhooksFanoutJob < BillingJob
  # Mostly basing this off the Zuora timeout of 2 minutes
  BASE_DELAY = T.let(5.minutes, ActiveSupport::Duration)

  sig { params(base_delay: ActiveSupport::Duration).void }
  def perform(base_delay: BASE_DELAY)
    webhooks = ::Billing::ZuoraWebhook.pending.ignoring_recent
    webhooks.find_each do |zuora_webhook|
      delay = rand(0..base_delay.to_i)

      ZuoraWebhookJob.set(wait: delay).perform_later(zuora_webhook)
    end
  end
end
