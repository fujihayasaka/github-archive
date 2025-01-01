# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module AdvancedSecurity
    class TalkToSomeone < Base

      sig { override.returns(String) }
      def title
        "Talk to someone from GitHub"
      end

      sig { override.returns(T.nilable(String)) }
      def task_link
        "https://github.com/security/contact-sales"
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        taskable.completed_onboarding_tasks.include?(task_key)
      end
    end
  end
end
