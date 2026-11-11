# typed: true
# frozen_string_literal: true

module PullRequests::PageData
  module StatusChecks
    class PullRequestPendingWorkflowApprovalSummary
      include GitHub::Memoizer
      include PendingWorkflowApprovalHelper

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
                  approvalRequiredMessage: pending_workflow_approval_message,
                  helpLink: pending_workflow_help_link,
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
        any_expired?(workflows_pending_approval)
      end

      sig { returns(T::Boolean) }
      private def has_all_expired_workflow_runs?
        all_expired?(workflows_pending_approval)
      end

      sig { returns(T::Boolean) }
      private def viewer_can_approve_workflow_runs?
        viewer_can_approve?(
          workflows_pending_approval,
          @pull_request.repository,
          @current_user
        )
      end

      sig { returns(String) }
      private def pending_workflow_approval_message
        approval_message(@pull_request.repository)
      end

      sig { returns(String) }
      private def pending_workflow_help_link
        approval_help_link(@pull_request.repository)
      end
    end
  end
end
