# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module AdvancedSecurity
    class EnableAdvancedSecurity < Base
      extend T::Sig

      sig { override.returns(String) }
      def title
        "Turn on Advanced Security"
      end

      sig { override.returns(String) }
      def task_link
        settings_org_security_analysis_path(organization, tip: "advanced_security")
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        taskable.completed_onboarding_tasks.include?(task_key)
      end
    end
  end
end
