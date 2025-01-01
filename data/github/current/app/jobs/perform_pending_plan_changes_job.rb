# typed: true
# frozen_string_literal: true

class PerformPendingPlanChangesJob < BillingJob
  queue_as :billing

  schedule interval: 1.hour, condition: -> { GitHub.billing_enabled? }

  def perform
    ::Billing::PendingPlanChange.incomplete.scheduled_for(GitHub::Billing.today).find_each do |change|
      RunPendingPlanChangeJob.set(wait: rand(1...600).seconds).perform_later(change)
    end
  end
end
