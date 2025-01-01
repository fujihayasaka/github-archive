# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RestorePullRequestHeadRef < Platform::Mutations::Base
      description "Restores a merged or closed pull request's head ref after it's been deleted"
      visibility :internal

      minimum_accepted_scopes ["public_repo"]

      argument :pull_request_id, ID, "ID of the closed or merged pull request whose head ref should be restored", required: true, loads: Objects::PullRequest

      field :pull_request, Objects::PullRequest, "The pull request whose head ref was restored.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, pull_request:, **inputs)
        permission.async_repo_and_org_owner(pull_request).then do |repo, org|
          permission.access_allowed?(:update_pull_request, repo: repo, resource: pull_request, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(pull_request:)
        pull_request.async_repository.then do |repository|
          context[:permission].authorize_content(:pull_request, :update, repo: repository)

          if pull_request.restore_head_ref(context[:viewer])
            { pull_request: pull_request }
          else
            raise Errors::Unprocessable.new("Could not restore head ref")
          end
        end
      end
    end
  end
end
