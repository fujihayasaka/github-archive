# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DependencyGraphDependent < Platform::Objects::Base
      description "A package dependent"

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
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      visibility :internal

      minimum_accepted_scopes ["public_repo"]

      field :cursor, String, null: true

      field :manifest_filename, String, description: "Filename of the manifest containing this dependent", null: true
      field :manifest_path, String, description: "Path of the manifest containing this dependent", null: true
      field :name, String, description: "The dependent name if applicable", null: true
      field :repository, Objects::Repository, description: "The repository containing the dependent", null: true, method: :async_repository

      url_fields prefix: :manifest_blob, description: "URL to the blob for this manifest path", null: true do |dependent|
        dependent.async_repository.then { dependent.manifest_blob_path }
      end
    end
  end
end
