# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PendingWorkflowApprovalRollup < Platform::Objects::Base
      include PendingWorkflowApprovalHelper

      description "Represents the status of workflow approvals in a rollup."

      required_capabilities [:mobile_only_schema_mask]

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_access?("Repository", object.repository)
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        repo = object.repository
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(
            :get_status_check_rollup,
            resource: repo,
            current_org: org,
            current_repo: repo,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def self.load_from_pull_request(repository, workflows_pending_approval)
        Platform::Models::PendingWorkflowApprovalRollup.new(
          repository: repository,
          workflows_pending_approval: workflows_pending_approval
        )
      end

      field :workflows_requiring_approval_count, Integer, null: false, description: "The number of workflows requiring approval."
      def workflows_requiring_approval_count
        @object.workflows_pending_approval.size
      end

      field :viewer_can_approve_workflow_runs, Boolean, null: false, description: "Indicates if the viewer can approve workflow runs."

      def viewer_can_approve_workflow_runs
        viewer_can_approve?(
          @object.workflows_pending_approval,
          @object.repository,
          context[:viewer]
        )
      end

      field :has_expired_workflow_runs, Boolean, null: false, description: "Indicates if there are expired workflow runs."

      def has_expired_workflow_runs
        any_expired?(@object.workflows_pending_approval)
      end

      field :approval_required_message, String, null: false, description: "The message displayed when approval is required."

      def approval_required_message
        approval_message(@object.repository)
      end

      field :help_link, Scalars::URI, null: false, description: "A link to help documentation."

      def help_link
        approval_help_link(@object.repository)
      end
    end
  end
end
