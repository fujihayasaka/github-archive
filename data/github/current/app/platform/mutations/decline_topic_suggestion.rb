# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeclineTopicSuggestion < Platform::Mutations::Base
      description "Rejects a suggested topic for the repository."

      minimum_accepted_scopes ["public_repo"]

      visibility :public, environments: [:dotcom]

      DeprecationNotice = {
        start_date: Date.new(2023, 12, 20),
        reason: "Suggested topics are no longer supported",
        superseded_by: nil,
        owner: "calvinchilds",
      }

      argument :repository_id, ID, "The Node ID of the repository.", required: false, loads: Objects::Repository, deprecated: DeprecationNotice
      argument :name, String, "The name of the suggested topic.", required: false, deprecated: DeprecationNotice
      argument :reason, Enums::TopicSuggestionDeclineReason, "The reason why the suggested topic is declined.", required: false, deprecated: DeprecationNotice

      field :topic, Objects::Topic, "The declined topic.", null: true, deprecated: DeprecationNotice

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository:, **inputs)
        repo = repository
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:edit_repo, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(repository:, **inputs)
        raise Errors::Unprocessable.new("Topic suggestions are not supported for #{repository.name_with_display_owner}.")
      end
    end
  end
end
