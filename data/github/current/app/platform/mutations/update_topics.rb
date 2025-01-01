# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateTopics < Platform::Mutations::Base
      description "Replaces the repository's topics with the given topics."

      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, "The Node ID of the repository.", required: true, loads: Objects::Repository
      argument :topic_names, [String], "An array of topic names.", required: true

      field :repository, Objects::Repository, "The updated repository.", null: true

      field :invalid_topic_names, [String], "Names of the provided topics that are not valid.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository:, **inputs)
        repo = repository
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:manage_topics, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(execution_errors:, repository:, topic_names:)
        unless repository.can_manage_topics?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to update the topics of #{repository.name_with_display_owner}.")
        end

        if repository.update_topics(topic_names, user: context[:viewer])
          { repository: repository, invalid_topic_names: nil }
        elsif repository.invalid_topic_names.any?
          repository.errors[:repository_topics].each do |error_message|
            execution_errors.add(Errors::Validation.new(error_message))
          end
          { repository: repository, invalid_topic_names: repository.invalid_topic_names }
        else
          raise Errors::Unprocessable.new("Could not apply the given topics at this time.")
        end
      end
    end
  end
end
