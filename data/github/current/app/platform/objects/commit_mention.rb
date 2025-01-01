# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CommitMention < Platform::Objects::Base
      description "Records @mentions happening in commit messages"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end

      visibility :internal

      minimum_accepted_scopes ["repo"]

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      global_id_field :id, description: "The Node ID of the CommitMention object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      field :repository, Objects::Repository, method: :async_repository, description: "Identifies the repository associated with the mention.", null: false

      field :author, Objects::User, description: "Identifies the user who created the mention.", null: false

      def author
        @object.async_repository.then do |repository|
          Loaders::GitObject.load(repository, @object.commit_id, expected_type: :commit).then do |commit|
            commit.author
          end
        end
      end

      field :commit, Objects::Commit, description: "Identifies the commit associated with the mention.", null: false

      def commit
        @object.async_repository.then do |repository|
          Loaders::GitObject.load(repository, @object.commit_id, expected_type: :commit)
        end
      end
    end
  end
end
