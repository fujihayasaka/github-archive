# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module EnterpriseCloudOnboard
  class GhasTrialEligibilityJob < ApplicationJob
    queue_as :ghas_trial

    retry_on ActiveJob::DeserializationError
    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    def perform(organization)
      return if GitHub.enterprise?

      GitHub.logger.info("job started",
        "gh.org.login": organization.login,
        "code.namespace": "EnterpriseCloudOnboard::GhasTrialEligibilityJob",
        "code.function": "perform"
      )

      result =
        if organization.business.present? && organization.invoiced?
          with_write { EnterpriseCloudOnboard::GhasTrialEligibility.new(organization).enterprise_eligibility_criteria }
        elsif organization.plan.business?
          with_write { EnterpriseCloudOnboard::GhasTrialEligibility.new(organization).remove_eligibility }
        else
          with_write { EnterpriseCloudOnboard::GhasTrialEligibility.new(organization).set_value }
        end

      GitHub.logger.info("job finished",
        "gh.org.login": organization.login,
        "gh.ghas_trial_eligibility.result": result,
        "code.namespace": "EnterpriseCloudOnboard::GhasTrialEligibilityJob",
        "code.function": "perform"
      )
    end
  end
end
