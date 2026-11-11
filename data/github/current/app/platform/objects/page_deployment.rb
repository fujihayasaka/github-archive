# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PageDeployment < Platform::Objects::Base
      description "GitHub Pages deployment for a given Repository."

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
      scopeless_tokens_as_minimum

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      global_id_field :id, description: "The Node ID of the PageDeployment object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      field :url, Scalars::URI, method: :async_url, description: "This URL at which this site can be accessed.", null: true

      field :status, Enums::PageBuildStatus, description: "The current build status of the Page.", null: true

      field :built_revision, Scalars::GitObjectID, method: :revision, description: "The git object ID corresponding to the commit currently deployed.", null: true

      field :build_type, Enums::PageBuildType, method: :async_build_type, description: "The process used to build the site.", null: true

      field :source_branch, String, method: :ref_name, description: "The git branch name used to build the site.", null: false

      field :source_path, String, method: :async_source_directory, description: "The subdirectory in the repository working tree used to build the site.", null: false
    end
  end
end
