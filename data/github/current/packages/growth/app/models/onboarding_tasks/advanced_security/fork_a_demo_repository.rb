# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module AdvancedSecurity
    class ForkADemoRepository < Base

      sig { override.returns(String) }
      def title
        "Fork a demo repository"
      end

      sig { override.returns(T.nilable(String)) }
      def task_link
        nil
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        taskable.completed_onboarding_tasks.include?(task_key)
      end
    end
  end
end
