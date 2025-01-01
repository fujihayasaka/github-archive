# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MarkPullRequestLatestRevisionAsSeen < Platform::Mutations::Base
      description "Marks a pull request latest revision as seen."
      minimum_accepted_scopes ["public_repo"]
      required_capabilities [:mobile_only_schema_mask]

      argument :pull_request_id, ID, "The ID of the pull request.", required: true, loads: Objects::PullRequest

      field :pull_request, Objects::PullRequest, "The pull request marked as seen.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull_request:, **inputs)
        permission.async_repo_and_org_owner(pull_request).then do |repo, org|
          permission.access_allowed? :get_pull_request, repo: repo, current_org: org, resource: pull_request, allow_integrations: true, allow_user_via_granular_actor: true
        end
      end

      def resolve(pull_request:, **inputs)
        pull_comparison = PullRequest::Comparison.find(
          pull: pull_request,
          start_commit_oid: pull_request.merge_base,
          end_commit_oid: pull_request.head_sha,
          base_commit_oid: pull_request.merge_base,
          viewer: context[:viewer]
        )

        pull_comparison.mark_as_seen(user: context[:viewer])

        { pull_request: pull_request }
      end
    end
  end
end
