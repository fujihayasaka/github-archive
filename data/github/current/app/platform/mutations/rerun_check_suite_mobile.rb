# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RerunCheckSuiteMobile < Platform::Mutations::Base
      include Platform::Helpers::GitHubAppValidation

      description "Re-runs a check suite for a mobile client"
      required_capabilities [:mobile_only_schema_mask]

      minimum_accepted_scopes ["repo"]

      argument :check_suite_id, ID, "The Node ID of the check suite to rerun", required: true, loads: Objects::CheckSuite, as: :check_suite
      argument :enable_debug_logging, Boolean, "Enable debug logging", required: false, default_value: false
      argument :only_failed_check_runs, Boolean, "Only rerun failed check runs", required: false, default_value: false

      field :check_suite, Objects::CheckSuite, "The check suite that was re-run", null: true

      error_fields

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, check_suite:, **inputs)
        permission.async_repo_and_org_owner(check_suite).then do |repo, _org|
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
        check_suite = inputs[:check_suite]
        enable_debug_logging = inputs[:enable_debug_logging]
        only_failed_check_runs = inputs[:only_failed_check_runs]

        unless allowed_to_modify_app?(app_id: check_suite.github_app_id) # effectively, a 403
          raise Platform::Errors::Forbidden.new("GitHub App `#{context[:integration].id}` can't manage check suite `#{check_suite.global_relay_id}`")
        end

        check_suite.rerequest(actor: context[:viewer], enable_debug_logging: enable_debug_logging, only_failed_check_runs: only_failed_check_runs, only_failed_check_suites: false)

        {
          check_suite: check_suite,
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
