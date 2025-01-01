# typed: true
# frozen_string_literal: true

class YearlyCycleNoticeStartJob < BillingJob
  queue_as :billing

  schedule interval: 24.hours, condition: -> { !GitHub.enterprise? }

  exempt_from_tenant_context_requirement

  def perform
    ::Billing::YearlyCycleNotice.run
  end
end
