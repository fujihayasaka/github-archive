# typed: true
# frozen_string_literal: true

class PerformManualDunningPeriodJob < BillingJob
  queue_as :billing

  schedule interval: 1.hour, condition: -> { GitHub.billing_enabled? }

  exempt_from_tenant_context_requirement

  def perform
    ::Billing::ManualDunningPeriod.created_before(Date.today).where(notification_attempts: 0).find_each do |manual_dunning_period|
      RunManualDunningPeriodJob.perform_later(manual_dunning_period)
    end

    ::Billing::ManualDunningPeriod.created_before(7.days.ago).where(notification_attempts: 1).find_each do |manual_dunning_period|
      RunManualDunningPeriodJob.perform_later(manual_dunning_period)
    end

    ::Billing::ManualDunningPeriod.created_before(14.days.ago).find_each do |manual_dunning_period|
      RunManualDunningPeriodJob.perform_later(manual_dunning_period)
    end
  end
end
