# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateWhitespacePreference < Platform::Mutations::Base
      visibility :internal
      description "Update the ignore whitespace preference for a user viewing a pull request"

      minimum_accepted_scopes ["user"]

      argument :ignore_whitespace, Boolean, description: "Whether the user prefers to ignore whitespace in diffs", required: true
      argument :pull_request_id, ID, description: "The Node ID of the pull request.", required: true, loads: Objects::PullRequest

      field :pull_request, Objects::PullRequest, "The updated pull request.", null: true
      field :user, Objects::User, "The updated user.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull_request:, **inputs)
        permission.async_repo_and_org_owner(pull_request).then do |repo, org|
          permission.access_allowed? :get_pull_request, repo: repo, current_org: org, resource: pull_request, allow_integrations: true, allow_user_via_granular_actor: true
        end
      end

      def resolve(ignore_whitespace:, pull_request:)
        if ignore_whitespace
          pull_request.set_ignore_whitespace_preference(context[:viewer])
        else
          pull_request.clear_ignore_whitespace_preference(context[:viewer])
        end

        {
          pull_request: pull_request,
          user: context[:viewer]
        }
      end
    end
  end
end
