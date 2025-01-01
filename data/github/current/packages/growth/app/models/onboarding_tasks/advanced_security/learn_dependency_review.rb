# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module AdvancedSecurity
    class LearnDependencyReview < Base

      sig { override.returns(String) }
      def title
        "Learn about dependency review"
      end

      sig { override.returns(String) }
      def task_link
        "#{GitHub.help_url}/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/reviewing-dependency-changes-in-a-pull-request#reviewing-dependencies-in-a-pull-request"
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        taskable.completed_onboarding_tasks.include?(task_key)
      end
    end
  end
end
