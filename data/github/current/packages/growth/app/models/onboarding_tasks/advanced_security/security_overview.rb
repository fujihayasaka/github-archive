# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module AdvancedSecurity
    class SecurityOverview < Base

      sig { override.returns(String) }
      def title
        "View your results in Security Overview"
      end

      sig { override.returns(String) }
      def task_link
        security_center_overview_dashboard_path(organization, tip: "security_overview")
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        taskable.completed_onboarding_tasks.include?(task_key)
      end
    end
  end
end
