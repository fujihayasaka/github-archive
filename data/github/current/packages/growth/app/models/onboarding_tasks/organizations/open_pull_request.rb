# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Organizations
    class OpenPullRequest < Base
      extend T::Sig

      sig { override.returns(String) }
      def title
        "Create a pull request"
      end

      sig { returns(T::Boolean) }
      def require_demo_repository?
        true
      end

      sig { override.returns(T.nilable(String)) }
      def task_link
        return unless (repo = demo_repo)
        compare_url = compare_path(repo, "main...#{OrganizationOnboard::DemoRepository::ACTIONS_WORKFLOW_BRANCH_NAME}")
        "#{compare_url}?show_onboarding_guide_tip=true"
      end

      sig { override.returns(String) }
      def icon_path
        "modules/dashboard/suggestions/pull-request.svg"
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        return false unless (repo = demo_repo)

        begin
          PullRequest.limit_execution_time.where(repository_id: repo.id).exists?
        rescue ActiveRecord::StatementTimeout
          false
        end
      end
    end
  end
end
