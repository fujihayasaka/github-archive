# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateCompletedWorkflowLogsAccess < Platform::Mutations::Base
      description "Creates access metadata for fetching completed workflow logs"
      mobile_only true

      minimum_accepted_scopes ["repo"]

      argument :check_run_id, ID, "The ID of the completed check run", required: true, loads: Objects::CheckRun, as: :check_run
      argument :step_number, Int, "The number of the step to fetch logs for; this is optional", required: false

      field :expires_at, Scalars::DateTime, "The time that the access expires at", null: true
      field :download_url, Scalars::URI, "The URL to download the logs", null: true

      error_fields

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, check_run:, **inputs)
        permission.async_repo_and_org_owner(check_run).then do |repo, _org|
          permission.access_allowed?(
            :read_actions_downloads,
            resource: repo,
            user: permission.viewer,
            current_org: nil,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
            enforce_oauth_app_policy: repo.private?
          )
        end
      end

      def check_run_log_url(check_run)
        if ActionsResults::Utils.is_results_url?(check_run.completed_log_url)
          actions_url = ActionsResults::Utils.actions_url(check_run.completed_log_url)
          if actions_url.nil? || check_run.check_suite.workflow_run.logs_via_results_service?
            return check_run.get_signed_completed_log_url
          else # we don't favor results, fallback to actions service
            return check_run.request_completed_log_url_from_actions_service(actions_url)
          end
        end

        check_run.request_completed_log_url_from_actions_service(check_run.completed_log_url)
      end

      def step_log_url(check_run, step_number:)
        check_step =
          if check_run.passthrough_steps?
            check_run.steps_from_backend.find { |step| step.number == step_number.to_i }
          else
            check_run.get_steps.find { |step| step.number == step_number.to_i }
          end

        if check_step.nil?
          raise Platform::Errors::Execution.new("Check step does not exist")
        end

        if ActionsResults::Utils.is_results_url?(check_step.completed_log_url)
          actions_url = ActionsResults::Utils.actions_url(check_step.completed_log_url)
          if actions_url.nil? || check_run.check_suite.workflow_run.logs_via_results_service?
            return check_step.get_signed_completed_log_url
          else # we don't favor results, fallback to actions service
            return check_step.request_completed_log_url_from_actions_service(actions_url)
          end
        end

        check_step.request_completed_log_url_from_actions_service(check_step.completed_log_url)
      end

      def resolve(**inputs)
        check_run = inputs[:check_run]
        step_number = inputs[:step_number]

        if check_run.expired_logs?
          error = Platform::Errors::Execution.new("Logs have expired")
        elsif check_run.completed_log_url.nil?
          error = Platform::Errors::Execution.new("Cannot generate access for check run with no completed log url. The job may be in-progress or in a non-completed state.")
        end

        if !error.nil?
          return {
            expires_at: nil,
            download_url: nil,
            errors: Array.wrap(error)
          }
        end

        if step_number
          result = step_log_url(check_run, step_number: step_number)
        else
          result = check_run_log_url(check_run)
        end

        if result.respond_to?(:call_succeeded?)
          unless result.call_succeeded?
            raise Errors::Execution.new("Request failed with status #{result.status}")
          end

          download_url = result.value.authenticated_url
        else
          download_url = result
        end

        if download_url.nil?
          return {
            expires_at: nil,
            download_url: nil,
            errors: Array.wrap(Platform::Errors::Execution.new("Unable to fetch logs."))
          }
        end

        params = Addressable::URI.parse(download_url).query_values
        expires_at = params["urlExpires"] || params["se"]

        {
          expires_at: expires_at,
          download_url: download_url,
          errors: []
        }
      end
    end
  end
end
