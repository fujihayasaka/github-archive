# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CommitRevision < Platform::Objects::Base
      description "A revision names a commit object."

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
      implements Interfaces::RepositoryNode

      global_id_field :id, description: "The Node ID of the CommitRevision object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      field :repository, Repository, "The repository associated with this revision.", null: false

      field :name, String, null: false, description: <<~MD
          The name that can be resolved to a commit.

          It uses what is called an extended SHA-1 syntax.

          Examples:
          * "dae86e1950b1277e545cee180551750029cfe735"
          * "dae86e"
          * "v1.7.4.2-679-g3bee7fb"
          * "HEAD"
          * "master"

          See https://www.git-scm.com/docs/git-rev-parse#_specifying_revisions for more examples.
        MD

      def name
        @object.name.dup.force_encoding("UTF-8")
      end

      field :directory, Objects::CommittishDirectory, "Look up directory under the commit tree", null: true do
        argument :path, String, "The file path", required: false
      end

      def directory(path: nil)
        @object.async_load_directory(path: path)
      end

      field :file, Objects::CommittishFile, "Look up file under the commit tree.", null: true do
        argument :path, String, "The file path.", required: true
      end

      def file(path:)
        @object.async_load_file(path: path)
      end

      field :commit, Objects::Commit, method: :async_commit, null: true, description: <<~MD
          The commit this revision resolves to.
        MD

      def self.load_from_global_id(id)
        Models::CommitRevision.load_from_global_id(id)
      end
    end
  end
end
