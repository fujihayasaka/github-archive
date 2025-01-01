# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CommittishDirectory < Platform::Objects::Base
      description "Represents a git tree that is bound under a commit."

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      minimum_accepted_scopes ["repo"]

      visibility :internal

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject
      implements Interfaces::CommittishObject
      implements Interfaces::RepositoryNode
      implements Interfaces::UniformResourceLocatable

      global_id_field :id, description: "The Node ID of the CommittishDirectory object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      url_fields description: "The HTTP URL for this directory" do |directory|
        directory.uri
      end

      field :repository, Repository, "The repository associated with this directory.", null: false
      field :revision, CommitRevision, "The commit revision object associated with this directory.", null: false

      field :file_path, String, null: false, description: <<~MD
        The directory's path from the tree root.

        Examples
        * "" (root directory is indicated by an empty string)
        * "lib"
        * "src/example/foo/bar"
      MD

      field :tree, Tree, "The tree object this directory path resolves to.", method: :async_object, null: false

      def self.load_from_global_id(id)
        Models::CommittishDirectory.load_from_global_id(id)
      end
    end
  end
end
