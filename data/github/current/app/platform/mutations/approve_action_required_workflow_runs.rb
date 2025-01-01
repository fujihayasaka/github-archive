# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ApproveActionRequiredWorkflowRuns < Platform::Mutations::Base
      description "Approve all of the action_required workflows on a pull request"
      minimum_accepted_scopes ["public_repo"]
      mobile_only true

      argument :pull_request_id, ID, "The node ID of the pull request", required: true, loads: Objects::PullRequest, as: :pull

      error_fields

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull:, **inputs)
        permission.async_repo_and_org_owner(pull).then do |repo, org|
          permission.access_allowed?(
            :write_actions,
            repo: repo,
            resource: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(pull:, **inputs)
        user = context[:viewer]
        errors = []

        pull.action_required_check_suites(head_sha: pull.head_sha).each do |check_suite|
          begin
            check_suite.rerequest(actor: user)
          rescue CheckSuite::ActionsDependency::ExpiredWorkflowRunError
            errors.append Platform::Errors::Forbidden.new("Unable to re-run workflow run #{check_suite.workflow_run.id} because it was created over a month ago")
          rescue CheckSuite::AlreadyRerunningError
            errors.append Platform::Errors::Forbidden.new("Unable to re-run workflow run #{check_suite.workflow_run.id} because it is already running")
          rescue CheckSuite::DisabledWorkflowError
            errors.append Platform::Errors::Forbidden.new("Unable to re-run workflow run #{check_suite.workflow_run.id} because the workflow is disabled")
          rescue CheckSuite::NotRerequestableError
            errors.append Platform::Errors::Forbidden.new("Unable to re-run workflow run #{check_suite.workflow_run.id}")
          end
        end

        { errors: errors }
      end
    end
  end
end
