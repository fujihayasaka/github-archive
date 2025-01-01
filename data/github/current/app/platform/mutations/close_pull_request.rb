# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ClosePullRequest < Platform::Mutations::Base
      description "Close a pull request."

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, "ID of the pull request to be closed.", required: true, loads: Objects::PullRequest

      field :pull_request, Objects::PullRequest, "The pull request that was closed.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull_request:, **inputs)
        permission.async_repo_and_org_owner(pull_request).then do |repo, org|
          permission.access_allowed?(:close_pull_request, repo: repo, resource: pull_request, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(pull_request:)
        pull_request.async_repository.then do |repository|
          context[:permission].authorize_content(:pull_request, :update, repo: repository)

          check_database_resource_update_rate_limit!(resource: pull_request, current_user: context[:viewer])

          if pull_request.closed? || pull_request.close(context[:viewer])
            { pull_request: pull_request }
          else
            raise Errors::Unprocessable.new("Could not close the pull request.")
          end
        end
      end
    end
  end
end
