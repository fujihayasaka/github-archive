# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ReleaseAsset < Platform::Objects::Base
      description "A release asset contains the content for a release asset."

      implements_node templates: [[:rra, :repo_id, :release_asset_id]], as: "RA", ready_date: Platform::Helpers::GlobalId::COHORT_2 do |release_asset|
        {
          prefix: :rra,
          repo_id: release_asset.repository_id,
          release_asset_id: release_asset.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, release_asset)
        release_asset.async_release.then do |release|
          permission.typed_can_access?("Release", release)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end

      scopeless_tokens_as_minimum

      created_at_field
      updated_at_field

      field :name, String, "Identifies the title of the release asset.", null: false
      field :url, Scalars::URI, description: "Identifies the URL of the release asset.", null: false

      def url
        @object.async_repository.then do
          @object.url
        end
      end

      field :download_url, Scalars::URI, description: "Identifies the URL where you can download the release asset via the browser.", null: false

      def download_url
        @object.async_release.then do
          @object.permalink
        end
      end

      field :release, Objects::Release, method: :async_release, description: "Release that the asset is associated with", null: true

      field :download_count, Integer, "The number of times this asset was downloaded", method: :downloads, null: false

      field :content_type, String, "The asset's content-type", method: :downloadable_content_type, null: false

      field :uploaded_by, User, method: :async_uploader, description: "The user that performed the upload", null: false

      field :size, Integer, "The size (in bytes) of the asset", null: false

      field :digest, String, "The SHA256 digest of the asset", null: true

      def self.load_from_global_id(id)
        Loaders::ActiveRecord.load(::ReleaseAsset, id.to_i)
      end
    end
  end
end
