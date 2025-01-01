# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RerunCheckRunMobile < Platform::Mutations::Base
      include Platform::Helpers::GitHubAppValidation

      description "Re-runs a check run for a mobile client requestor"
      required_capabilities [:mobile_only_schema_mask]

      minimum_accepted_scopes ["repo"]

      argument :check_run_id, ID, "The Node ID of the check run associated with the check suite to rerun", required: true, loads: Objects::CheckRun, as: :check_run
      argument :enable_debug_logging, Boolean, "Enable debug logging", required: false, default_value: false

      field :check_suite, Objects::CheckSuite, "The restarted check suite", null: true

      error_fields

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, check_run:, **inputs)
        permission.async_repo_and_org_owner(check_run).then do |repo, _org|
          permission.access_allowed?(
            :write_actions,
            resource: repo,
            current_repo: nil,
            current_org: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(**inputs)
        check_run = inputs[:check_run]
        enable_debug_logging = inputs[:enable_debug_logging]

        unless allowed_to_modify_app?(app_id: check_run.check_suite.github_app_id) # effectively, a 403
          raise Platform::Errors::Forbidden.new("GitHub App `#{context[:integration].id}` can't manage check run `#{check_run.global_relay_id}`")
        end

        if check_run.is_actions_check_run?
          check_run.actions_rerequest(actor: context[:viewer], enable_debug_logging: enable_debug_logging)
        else
          check_run.rerequest(actor: context[:viewer])
        end

        {
          check_suite: check_run.check_suite,
          errors: []
        }

        rescue CheckSuite::ActionsDependency::ExpiredWorkflowRunError
          raise Platform::Errors::Forbidden.new("Unable to retry this check suite because it was created over a month ago")
        rescue CheckSuite::AlreadyRerunningError
          raise Platform::Errors::Forbidden.new("This check suite is already running")
        rescue CheckSuite::DisabledWorkflowError
          raise Platform::Errors::Forbidden.new("Unable to retry disabled workflow")
        rescue CheckSuite::NotRerequestableError
          raise Platform::Errors::Forbidden.new("This check suite cannot be retried")
      end
    end
  end
end
