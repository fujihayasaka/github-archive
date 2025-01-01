# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DeletedIssue < Platform::Objects::Base
      description "A record of the deleted issue."
      visibility :internal

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_repository.then do |repo|
          repo.async_owner.then do |owner|
            current_org = owner if owner.is_a?(::Organization)
            permission.access_allowed?(:list_issues, repo: repo, current_org: current_org, user: permission.viewer, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_repository.then do |repo|
          repo.readable_by?(permission.viewer)
        end
      end

      scopeless_tokens_as_minimum

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      global_id_field :id, description: "The Node ID of the DeletedIssue object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      database_id_field

      field :number, Integer, description: "The number of the issue that was deleted.", null: false
      field :old_issue_id, Integer, description: "The old id of the issue that was deleted.", null: true
      field :repository, Objects::Repository, method: :async_repository, description: "The repository that this issue was deleted from.", null: false
      field :deleted_by, Interfaces::Actor, method: :async_deleted_by, description: "The actor that deleted this issue.", null: false
    end
  end
end
