# typed: true
# frozen_string_literal: true

class PerformOFACDowngradesJob < ApplicationJob
  queue_as :trade_controls
  retry_on_dirty_exit

  schedule interval: 12.hours, condition: -> { GitHub.billing_enabled? }

  def perform
    OFACDowngrade.incomplete.scheduled_for(GitHub::Billing.today).find_each do |downgrade|
      OFACComplianceDowngradeJob.perform_later(downgrade)
    end
  end
end
