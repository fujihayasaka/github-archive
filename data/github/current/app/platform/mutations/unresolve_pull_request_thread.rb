# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnresolvePullRequestThread < Platform::Mutations::Base
      description "Marks a PullRequestThread as unresolved."

      visibility :internal

      minimum_accepted_scopes ["public_repo"]

      argument :thread_id, ID, required: true, description: "The ID of the thread to resolve", loads: Objects::PullRequestThread

      field :thread, Objects::PullRequestThread, "The thread to unresolve.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, thread:, **inputs)
        thread.async_pull_request.then do |pull|
          permission.async_repo_and_org_owner(pull).then do |repo, org|
            permission.access_allowed?(:resolve_pull_request_review_thread, repo: repo, current_org: org, resource: pull, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      def resolve(thread:)
        check_database_resource_update_rate_limit!(resource: thread.review_thread, current_user: context[:viewer])

        thread.review_thread.unresolve(unresolver: @context[:viewer])
        {
          thread: thread,
        }
      end
    end
  end
end
