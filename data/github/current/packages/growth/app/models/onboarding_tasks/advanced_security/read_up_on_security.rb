# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module AdvancedSecurity
    class ReadUpOnSecurity < Base

      sig { override.returns(String) }
      def title
        "Read up on security"
      end

      sig { override.returns(T.nilable(String)) }
      def task_link
        "https://github.blog/security/"
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        taskable.completed_onboarding_tasks.include?(task_key)
      end
    end
  end
end
