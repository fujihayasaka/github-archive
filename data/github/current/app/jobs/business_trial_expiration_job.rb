# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class BusinessTrialExpirationJob < ApplicationJob
  schedule interval: 1.hour, condition: -> { !GitHub.single_business_environment? }

  queue_as :business_trial_expiration
  retry_on_dirty_exit

  MAX_BUSINESSES = 100

  # Public - scheduled job to downgrade expired enterprise account trials
  def perform
    begin
      self.class.trials_to_be_expired.each do |business|
        Failbot.push_sensitive(business: business.slug)
        GitHub::CurrentTenant.set(business) if GitHub.multi_tenant_enterprise?
        with_write { business.expire_trial }
      end
    rescue NoMethodError => error
      report_error(error)
    end
  end

  def self.trials_to_be_expired
    Business.trial_expired.trial_not_completed.trial_conversion_not_initiated.limit(MAX_BUSINESSES)
  end

  private

  def report_error(error)
    Failbot.report(error)
  end
end
