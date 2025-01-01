# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Organizations
    class RunCi < Base
      sig { override.returns(String) }
      def title
        "Run a continuous integration test"
      end

      sig { override.returns(T.nilable(String)) }
      def task_link
        return unless (repo = demo_repo)
        workflow_runs_list_path(organization, repo.name, "proof-html.yml", show_workflow_tip: true)
      end

      sig { returns(T::Boolean) }
      def require_demo_repository?
        true
      end

      sig { override.returns(String) }
      def icon_path
        "modules/dashboard/suggestions/continuous-integration.svg"
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        return false unless (repo = demo_repo)

        begin
          Actions::WorkflowRun.limit_execution_time.where(repository_id: repo.id, name: "Proof HTML", event: "workflow_dispatch").exists?
        rescue ActiveRecord::StatementTimeout
          false
        end
      end
    end
  end
end
