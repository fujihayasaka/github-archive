# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Organizations
    class CustomizePermission < Base
      TASK_KEY = T.let(:customize_permission.freeze, Symbol)

      sig { override.returns(String) }
      def title
        "Customize members' permissions"
      end

      sig { override.returns(String) }
      def task_link
        settings_org_member_privileges_path(organization, enable_tip: true)
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        with_database_error_fallback(fallback: false) do
          organization.completed_onboarding_tasks.include?(TASK_KEY) ||
            [:admin, :write].include?(organization.default_repository_permission)
        end
      end

      sig { override.returns(String) }
      def icon_path
        "modules/dashboard/suggestions/permissions.svg"
      end
    end
  end
end
