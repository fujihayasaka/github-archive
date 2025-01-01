# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MarkPullRequestReadyForReview < Platform::Mutations::Base
      description "Marks a pull request ready for review."
      minimum_accepted_scopes ["public_repo"]
      argument :pull_request_id, ID, "ID of the pull request to be marked as ready for review.", required: true, loads: Objects::PullRequest

      field :pull_request, Objects::PullRequest, "The pull request that is ready for review.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull_request:, **inputs)
        permission.async_repo_and_org_owner(pull_request).then do |repo, org|
          permission.access_allowed?(:mark_pull_request_ready_for_review, repo: repo, current_org: org, resource: pull_request, allow_user_via_granular_actor: true, allow_integrations: true)
        end
      end

      def resolve(pull_request:, **inputs)
        unless pull_request.can_change_draft_state?(context[:viewer])
          message = "#{context[:viewer].display_login} does not have permission to mark the pull request #{pull_request.global_relay_id} ready for review."
          raise Errors::Forbidden.new(message)
        end

        pull_request.ready_for_review!(user: context[:viewer])

        { pull_request: pull_request }
      end
    end
  end
end
