# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class BillingUpdateExchangeRatesJob < ApplicationJob
  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }

  queue_as :billing

  exempt_from_tenant_context_requirement

  def perform
    with_write { GitHub::Billing::Currency.update_rates(force: true) }
  end
end
