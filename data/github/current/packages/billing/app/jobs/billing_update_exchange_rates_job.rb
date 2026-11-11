# typed: true
# frozen_string_literal: true

class BillingUpdateExchangeRatesJob < BillingJob
  schedule interval: 1.hour, condition: -> { GitHub.billing_enabled? }

  exempt_from_tenant_context_requirement

  def perform
    with_write { GitHub::Billing::Currency.update_rates(force: true) }
  end
end
