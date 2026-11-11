# typed: true
# frozen_string_literal: true

module Billing
  class CheckUnprocessedWebhooksJob < ApplicationJob
    queue_as :billing
    schedule interval: 5.minutes, condition: -> { GitHub.billing_enabled? }

    WEBHOOK_KINDS = {
      stripe: -> { ::Billing::StripeWebhook },
      zuora: -> { ::Billing::ZuoraWebhook.not_sales_serve },
    }.freeze

    exempt_from_tenant_context_requirement

    attr_reader :cutoff

    # Public: Report metrics on the number of unprocessed Zuora and Stripe
    # webhooks that are older than the recency threshold of 5 minutes
    #
    # Returns nothing
    def perform
      WEBHOOK_KINDS.each do |kind, root_scope_proc|
        check_unprocessed_webhooks(kind, root_scope_proc.call)
      end
    end

    private

    def check_unprocessed_webhooks(kind, root_scope)
      unprocessed_webhooks = root_scope.pending.ignoring_recent

      # Workaround to process and avoid alerting on webhooks that were never performed due to a Hydro publishing issue
      # See https://github.com/github/data-pipelines/issues/3374
      if kind == :zuora && FeatureFlag.vexi.enabled?(:billing_handle_unprocessed_webhooks, default: false)
        unprocessed_webhooks = unprocessed_webhooks.reject { |webhook| webhook.performed_at.nil? }
        root_scope.pending.stale.each { |webhook| retry_if_not_performed(webhook) }
      end

      GitHub.dogstats.gauge("#{kind}.unprocessed_webhooks.count", unprocessed_webhooks.count)

      return if unprocessed_webhooks.empty?

      max_age_in_milliseconds = (Time.now.to_i - unprocessed_webhooks.minimum(:created_at).to_i) * 1000
      GitHub.dogstats.gauge("#{kind}.unprocessed_webhooks.max_age", max_age_in_milliseconds)
    end

    sig { params(webhook: Billing::ZuoraWebhook).void }
    def retry_if_not_performed(webhook)
      return unless webhook.is_a?(Billing::ZuoraWebhook)
      return unless webhook.performed_at.nil?

      GitHub.dogstats.increment("billing.check_unprocessed_webhooks_job.retry_if_not_performed")
      GitHub.logger.info(
        "Retrying unprocessed zuora webhook",
        "code.namespace" => self.class.name,
        "code.function" => "retry_if_not_performed",
        "gh.billing.zuora.webhook.id" => webhook.id,
        "gh.billing.zuora.webhook.created_at" => webhook.created_at,
        "gh.billing.zuora.webhook.updated_at" => webhook.updated_at
      )

      ZuoraWebhookJob.perform_later(webhook)
    end
  end
end
