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
          settings_org_security_products_path(organization, tip: "recommended_settings")
        end

        sig { override.returns(T::Boolean) }
        def verify_task
          RepositorySecurityConfiguration.exists?(organization_id: organization.id)
        end
      end
    end
  end
end
