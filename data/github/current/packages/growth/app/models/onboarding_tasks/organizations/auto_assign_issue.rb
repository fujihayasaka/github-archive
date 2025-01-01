# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Organizations
    class AutoAssignIssue < Base
      extend T::Sig

      include ActionView::Helpers

      sig { override.returns(T::Boolean) }
      def verify_task
        has_auto_assign_workflow?
      end

      sig { override.returns(String) }
      def title
        "Auto-assign new issues"
      end

      sig { returns(T::Boolean) }
      def require_demo_repository?
        true
      end

      sig { override.returns(T.nilable(String)) }
      def task_link
        return unless (repo = demo_repo)
        "#{blob_view_path(".github/workflows/auto-assign.yml", repo.default_branch, repo)}?enable_tip=true"
      end

      sig { returns(String) }
      def success_message_html
        safe_join(["Your auto-assign workflow ran! It may take approximately 30 seconds for your automatic assignee to appear. To see the progress of any workflow, visit ", link_to("your repo's Actions tab", actions_path(organization, demo_repo))])
      end

      sig { override.returns(String) }
      def icon_path
        "modules/dashboard/suggestions/protected-branches.svg"
      end

      private

      sig { returns(T::Boolean) }
      def has_auto_assign_workflow?
        return false unless (repo = demo_repo)

        Actions::WorkflowRun.where(repository_id: repo.id, name: "Auto Assign").exists?
      end
    end
  end
end
