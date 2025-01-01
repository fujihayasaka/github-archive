# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module EnterpriseOnboarding
  class ExpireGhasTrialJob < ApplicationJob
    queue_as :ghas_trial

    schedule interval: 12.hours, condition: -> { !GitHub.enterprise? }

    retry_on_dirty_exit

    def perform
      expired_configurations.find_each do |config|
        billable_entity = config.target
        next unless billable_entity
        next unless exceeded_trial_days?(billable_entity, config.created_at)

        expire_ghas_trial(billable_entity)
      end
    end

    private

    def exceeded_trial_days?(billable_entity, trial_started_at)
      trial_number_of_days = billable_entity.advanced_security_trial_number_of_days.days
      trial_started_at + trial_number_of_days + 1.day < Time.current
    end

    def expired_configurations
      Configuration::Entry.named(Configurable::AdvancedSecurityTrialConfig::ADVANCED_SECURITY_TRIAL_KEY)
        .with_true_value
    end

    def expire_ghas_trial(account)
      with_write do
        EnterpriseCloudOnboard::GhasTrial.new(actor: User.ghost, billable_entity: account).disable
      end
    end
  end
end
