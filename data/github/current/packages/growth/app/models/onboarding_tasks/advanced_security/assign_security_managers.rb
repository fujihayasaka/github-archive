# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module AdvancedSecurity
    class AssignSecurityManagers < Base

      sig { override.returns(String) }
      def title
        "Assign security manager roles"
      end

      sig { override.returns(String) }
      def task_link
        settings_org_role_assignments_new_path(organization, tip: "security_managers")
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        SecurityProduct::SecurityManagers.new(@organization).team_ids.any?
      end
    end
  end
end
