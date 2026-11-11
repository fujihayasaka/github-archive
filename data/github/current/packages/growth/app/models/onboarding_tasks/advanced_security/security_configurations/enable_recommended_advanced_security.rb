# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module AdvancedSecurity
    module SecurityConfigurations
      class EnableRecommendedAdvancedSecurity < Base
        sig { override.returns(String) }
        def title
          "Enable Advanced Security"
        end

        sig { override.returns(String) }
        def task_link
          new_quick_setup_configuration_path(organization_id: organization)
        end

        sig { override.returns(T::Boolean) }
        def verify_task
          RepositorySecurityConfiguration.exists?(organization_id: organization.id)
        end
      end
    end
  end
end
