# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module AdvancedSecurity
    module SecurityConfigurations
      class ProtectNewRepositories < Base
        extend T::Sig

        sig { override.returns(String) }
        def title
          "Protect new repositories"
        end

        sig { override.returns(String) }
        def task_link
          settings_org_security_configurations_view_path(organization, tip: "protect_new_repositories")
        end

        sig { override.returns(T::Boolean) }
        def verify_task
          SecurityConfigurationDefault.where(target: organization, default_for_new_public_repos: true)
          .or(SecurityConfigurationDefault.where(target: organization, default_for_new_private_repos: true))
          .exists?
        end
      end
    end
  end
end
