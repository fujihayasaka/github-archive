# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CancelWorkflowRun < Platform::Mutations::Base
      include Platform::Helpers::GitHubAppValidation

      description "Cancels a workflow run"
      mobile_only true

      minimum_accepted_scopes ["repo"]

      argument :check_suite_id, ID, "The Node ID of the check suite to cancel", required: true, loads: Objects::CheckSuite, as: :check_suite

      field :success, Boolean, "Did the cancel workflow run operation succeed?", null: true

      error_fields

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, check_suite:, **inputs)
        permission.async_repo_and_org_owner(check_suite).then do |repo, _org|
          permission.access_allowed?(
            :write_actions,
            resource: repo,
            user: permission.viewer,
            current_repo: nil,
            current_org: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(**inputs)
        check_suite = inputs[:check_suite]

        unless allowed_to_modify_app?(app_id: check_suite.github_app_id) # effectively, a 403
          raise Platform::Errors::Forbidden.new("GitHub App `#{context[:integration].id}` can't manage check suite `#{check_suite.global_relay_id}`")
        end

        if check_suite.workflow_run.nil?
          raise Platform::Errors::Forbidden.new("Cannot cancel a check suite without a workflow run")
        end
        if check_suite.completed?
          raise Platform::Errors::Forbidden.new("Cannot cancel a check suite that has already completed")
        end

        result = check_suite.cancel(actor: context[:viewer])

        {
          success: true,
          errors: []
        }

      end
    end
  end
end
