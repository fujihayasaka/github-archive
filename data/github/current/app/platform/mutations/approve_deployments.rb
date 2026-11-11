# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ApproveDeployments < Platform::Mutations::Base
      include GateRequestHelper

      description "Approve all pending deployments under one or more environments"

      minimum_accepted_scopes ["public_repo"]

      argument :workflow_run_id, ID, "The node ID of the workflow run containing the pending deployments.", required: true, loads: Objects::WorkflowRun, as: :workflow_run
      argument :environment_ids, [ID], "The ids of environments to reject deployments", required: true
      argument :comment, String, "Optional comment for approving deployments", required: false, default_value: ""

      error_fields
      field :deployments, [Objects::Deployment], "The affected deployments.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, workflow_run:, **inputs)
        workflow_run.async_check_suite.then do |check_suite|
          permission.async_repo_and_org_owner(check_suite).then do |repo, org|
            permission.access_allowed?(:approve_deployments,
              resource: repo,
              current_repo: repo,
              current_org: org,
              allow_integrations: true,
              allow_user_via_granular_actor: true)
          end
        end
      end

      def resolve(workflow_run:, **inputs)
        user = context[:viewer]
        ids = inputs[:environment_ids].map { |id| Platform::Helpers::NodeIdentification.from_global_id(id)[1].to_i }
        check_suite = workflow_run.check_suite

        pending_gate_requests = check_suite.pending_approval_gate_requests_in_environments(user, ids)

        if pending_gate_requests.size < ids.size
          raise Errors::Forbidden.new("#{context[:viewer].display_login} is not a valid reviewer or at least one deployment was already reviewed by the user.")
        end

        deployments = pending_gate_requests.map(&:check_run).map(&:deployment)

        if deployments.empty?
          raise Errors::Validation.new("No pending deployment in workflow run `#{workflow_run.global_relay_id}` to approve")
        end

        begin
          GateApprovalLog.approve_or_reject_requests(context[:viewer], pending_gate_requests, "approved", inputs[:comment])
        rescue ArgumentError => e
          raise Errors::Validation.new(e.message)
        end

        { deployments: deployments, errors: [] }
      end
    end
  end
end
