# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Billing
  class CheckUnprocessedSalesServeWebhooksJob < BillingJob
    schedule interval: 5.minutes, condition: -> { GitHub.billing_enabled? }

    WEBHOOK_KINDS = {
      zuora: -> { ::Billing::ZuoraWebhook },
    }.freeze

    exempt_from_tenant_context_requirement

    attr_reader :cutoff

    # Public: Report metrics on the number of unprocessed Zuora
    # webhooks that are older than the recency threshold of 5 minutes
    # Webhooks SALES_SERVE_KINDS
    # Sends a Slack notification to #sales-operations when a new unprocessed webhook is found

    def perform
      WEBHOOK_KINDS.each do |kind, root_scope_proc|
        check_unprocessed_sales_serve_webhooks(kind, root_scope_proc.call)
      end
    end

    private

    def check_unprocessed_sales_serve_webhooks(kind, root_scope)
      unprocessed_sales_serve_webhooks = root_scope.pending.ignoring_recent.invoiced

      GitHub.dogstats.gauge("#{kind}.unprocessed_sales_serve_webhooks.count", unprocessed_sales_serve_webhooks.count)

      if unprocessed_sales_serve_webhooks.any?
        max_age_in_milliseconds = (Time.now.to_i - unprocessed_sales_serve_webhooks.minimum(:created_at).to_i) * 1000
        GitHub.dogstats.gauge("#{kind}.unprocessed_sales_serve_webhooks.max_age", max_age_in_milliseconds)
        unprocessed_sales_serve_webhooks.each do |webhook|
          with_write { Billing::SalesServeWebhookNotifier.new(webhook).send_notification }
        end
      end
    end
  end
end
