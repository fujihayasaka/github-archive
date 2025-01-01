# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryImage < Platform::Objects::Base
      description "An image for a repository."
      visibility :under_development
      minimum_accepted_scopes ["repo"]
      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, repo_image)
        repo_image.async_repository.then do |repo|
          permission.typed_can_access?("Repository", repo)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for a Marketplace::ListingScreenshot object
      def self.async_viewer_can_see?(permission, repo_image)
        repo_image.async_repository.then do |repo|
          permission.typed_can_see?("Repository", repo)
        end
      end

      global_id_field :id, description: "The Node ID of the RepositoryImage object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject
      database_id_field
      created_at_field
      updated_at_field

      field :content_type, String, "The content type of the image.", null: false

      field :size, Int, description: "The size of the image in bytes.", null: false

      field :url, Scalars::URI, description: "The URL to the image.", null: false

      def url
        @object.storage_external_url(@context[:viewer])
      end

      field :uploader, Objects::User, description: "The user who uploaded the image.",
        visibility: :internal, null: false, method: :async_uploader

      field :name, String, description: "The original file name that was uploaded.",
        visibility: :internal, null: false
    end
  end
end
