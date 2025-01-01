# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ReopenPullRequest < Platform::Mutations::Base
      description "Reopen a pull request."

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, "ID of the pull request to be reopened.", required: true, loads: Objects::PullRequest

      field :pull_request, Objects::PullRequest, "The pull request that was reopened.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull_request:, **inputs)
        permission.async_repo_and_org_owner(pull_request).then do |repo, org|
          permission.access_allowed?(:update_pull_request, repo: repo, current_org: org, resource: pull_request, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(pull_request:)
        pull_request.async_repository.then do |repository|
          context[:permission].authorize_content(:pull_request, :update, repo: repository)

          if pull_request.open? || pull_request.open(context[:viewer])
            { pull_request: pull_request }
          else
            raise Errors::Unprocessable.new("Could not open the pull request.")
          end
        end
      end
    end
  end
end
