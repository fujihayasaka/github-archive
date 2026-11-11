# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestStatus < Platform::Objects::Base
      docs_category :pulls
      include GitHub::Memoizer

      description "Represents the status checks on a pull request."

      required_capabilities :mobile_only_schema_mask, :access_pull_request_mergebox_graphql_api

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.async_repo_and_org_owner(object.pull_request).then do |repo, org|
          permission.access_allowed?(:read_status, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.pull_request.async_repository.then do |source|
          permission.typed_can_see?("Repository", source)
        end
      end

      field :status_checks, Connections.define(Objects::StatusCheck), numeric_pagination_enabled: true, description: "The status checks for the PR's head ref", null: true, connection: true

      def status_checks
        status_check_models = @object.status_checks.map do |status|
          Platform::Models::StatusCheck.new(
            status: status,
            repository_id: @object.pull_request.repository_id,
            pull_request: @object.pull_request
          )
        end
        checks = StableSorter.new(status_check_models).sort_by do |status_check|
          StatusCheckConfig::STATE_SORT_ORDER[status_check.status.state]
        end
        ArrayWrapper.new(checks)
      end

      field :status_rollup, Objects::StatusRollup, null: false, description: "The rollup of status checks."

      def status_rollup
        Objects::StatusRollup.load_from_status_checks(@object.pull_request.repository, @object.status_checks, pending_workflow_approval)
      end

      field :pending_workflow_approval_rollup, Objects::PendingWorkflowApprovalRollup, null: true, description: "The rollup of pending workflow approvals."

      def pending_workflow_approval_rollup
        return nil if pending_workflow_approval.empty?
        Objects::PendingWorkflowApprovalRollup.load_from_pull_request(@object.pull_request.repository, pending_workflow_approval)
      end

      sig { returns(T::Array[::CheckSuite]) }
      memoize private def pending_workflow_approval
        @object.pull_request.action_required_check_suites(head_sha: @object.pull_request.head_sha)
      end
    end
  end
end
