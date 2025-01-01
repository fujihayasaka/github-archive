# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ConvertPullRequestToDraft < Platform::Mutations::Base
      description "Converts a pull request to draft"
      minimum_accepted_scopes ["public_repo"]
      argument :pull_request_id, ID, "ID of the pull request to convert to draft", required: true, loads: Objects::PullRequest

      field :pull_request, Objects::PullRequest, "The pull request that is now a draft.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull_request:, **inputs)
        permission.async_repo_and_org_owner(pull_request).then do |repo, org|
          permission.access_allowed?(:mark_pull_request_ready_for_review, repo: repo, current_org: org, resource: pull_request, allow_user_via_granular_actor: true, allow_integrations: true)
        end
      end

      def resolve(pull_request:, **inputs)
        return unless pull_request.ready_for_review?

        unless pull_request.can_convert_to_draft?(context[:viewer])
          message = "#{context[:viewer].display_login} does not have permission to convert the pull request #{pull_request.global_relay_id} to draft."
          raise Errors::Forbidden.new(message)
        end

        begin
          pull_request.convert_to_draft(user: context[:viewer])
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
          raise Errors::Validation.new("Could not convert the pull request back to draft")
        end

        { pull_request: pull_request }
      end
    end
  end
end
