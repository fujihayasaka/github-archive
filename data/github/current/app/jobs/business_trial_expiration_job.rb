# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class BusinessTrialExpirationJob < ApplicationJob
  schedule interval: 1.hour, condition: -> { !GitHub.single_business_environment? }

  queue_as :business_trial_expiration
  retry_on_dirty_exit

  BATCH_SIZE = 1000

  # Public - scheduled job to downgrade expired enterprise account trials
  def perform
    self.class.trials_to_be_expired.in_batches(of: BATCH_SIZE) do |batch|
      batch.each do |business|
        Failbot.push_sensitive(business: business.slug)
        with_write { business.expire_trial }
      rescue NoMethodError => error
        report_error(error)
      end
    end
  end

  def self.trials_to_be_expired
    Business.trial_expired.trial_not_completed.trial_conversion_not_initiated
  end

  private

  def report_error(error)
    Failbot.report(error)
  end
end
