# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Organizations
    class DependabotSecurityUpdates < Base
      sig { override.returns(String) }
      def title
        "Get automatic security updates"
      end

      sig { override.returns(String) }
      def task_link
        settings_org_security_analysis_path(organization, show_update_tip: true)
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        organization.security_alerts_enabled_for_new_repos?
      end

      sig { override.returns(String) }
      def icon_path
        "modules/dashboard/suggestions/dependencies.svg"
      end
    end
  end
end
