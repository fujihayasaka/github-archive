# typed: true
# frozen_string_literal: true

module PullRequests::PageData
  module StatusChecks
    class PullRequestPendingWorkflowApprovalSummary
      include GitHub::Memoizer

      sig { params(pull_request: PullRequest, current_user: T.nilable(User)).void }
      def initialize(pull_request:, current_user:)
        @pull_request = pull_request
        @current_user = current_user
      end

      sig { returns(T.nilable(PullRequests::PageData::StatusChecksSerializer::PullRequestPendingWorkflowApprovalRollup)) }
      def rollup
        if has_workflows_pending_approval?
          PullRequests::PageData::StatusChecksSerializer::PullRequestPendingWorkflowApprovalRollup.new(
                  workflowsRequiringApprovalCount: workflows_pending_approval.size,
                  viewerCanApproveWorkflowRuns: viewer_can_approve_workflow_runs?,
                  hasExpiredWorkflowRuns: has_expired_workflow_runs?,
                  approvalRequiredMessage: approval_message,
                  helpLink: help_link,
                )
        else
          nil
        end
      end

      sig { returns(T::Boolean) }
      def has_workflows_pending_approval?
        workflows_pending_approval.size > 0
      end

      sig { returns(T::Array[CheckSuite]) }
      memoize private def workflows_pending_approval
        # Workflows that are pending approval do not yet have associated check runs. They only have check suites.
        # TODO: If a `CheckStatus` row is ever needed, consider moving this loading into the `StatusCheckFinder` and returning an in-memory object
        @pull_request.action_required_check_suites(head_sha: @pull_request.head_sha)
      end

      sig { returns(T::Boolean) }
      private def has_expired_workflow_runs?
        workflows_pending_approval.any?(&:expired_workflow_run?)
      end

      sig { returns(T::Boolean) }
      private def has_all_expired_workflow_runs?
        workflows_pending_approval.all?(&:expired_workflow_run?)
      end

      sig { returns(T::Boolean) }
      private def viewer_can_approve_workflow_runs?
        !has_all_expired_workflow_runs? && !!@pull_request.repository&.writable_by?(@current_user)
      end

      sig { returns(String) }
      private def approval_message
        if @pull_request.repository&.private?
          "Workflows will not run until approved by a user with write permissions."
        else
          "This workflow requires approval from a maintainer."
        end
      end

      sig { returns(String) }
      private def help_link
        if @pull_request.repository&.private?
          "#{GitHub.help_url}/actions/managing-workflow-runs/approving-workflow-runs-from-private-forks"
        else
          "#{GitHub.help_url}/actions/managing-workflow-runs/approving-workflow-runs-from-public-forks"
        end
      end
    end
  end
end
