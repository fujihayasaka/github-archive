# typed: true
# frozen_string_literal: true

class PerformManualDunningPeriodJob < BillingJob
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

    # The following queries enqueue jobs for all manual dunning periods in the specified time ranges.
    # This queries for ManualDunningPeriod meeting this criteria: 7.days.ago <= created_at < 1.day.ago
    ::Billing::ManualDunningPeriod.where(created_at: 7.days.ago...1.day.ago).where(notification_attempts: 1).find_each do |manual_dunning_period|
      RunManualDunningPeriodJob.perform_later(manual_dunning_period)
    end

    # This queries for ManualDunningPeriod meeting this criteria: 14.days.ago <= created_at < 2.days.ago
    ::Billing::ManualDunningPeriod.where(created_at: 14.days.ago...2.days.ago).where(notification_attempts: 2).find_each do |manual_dunning_period|
      RunManualDunningPeriodJob.perform_later(manual_dunning_period)
    end
  end
end
