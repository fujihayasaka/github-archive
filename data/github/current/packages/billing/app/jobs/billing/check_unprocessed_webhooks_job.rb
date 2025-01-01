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

      GitHub.dogstats.gauge("#{kind}.unprocessed_webhooks.count", unprocessed_webhooks.count)

      if unprocessed_webhooks.any?
        max_age_in_milliseconds = (Time.now.to_i - unprocessed_webhooks.minimum(:created_at).to_i) * 1000
        GitHub.dogstats.gauge("#{kind}.unprocessed_webhooks.max_age", max_age_in_milliseconds)
      end
    end
  end
end
