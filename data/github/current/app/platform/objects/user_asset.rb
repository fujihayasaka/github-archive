# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class UserAsset < Platform::Objects::Base
      implements Platform::Interfaces::RepositoryNode

      description "Image or video uploaded by a user, often to issue or pull request comments"

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

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
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      implements_node templates: [[:ua, :user_id, :id]], as: "UA", ready_date: "1970-01-01" do |user_asset|
        {
          prefix: :ua,
          user_id: user_asset.user_id,
          id: user_asset.id
        }
      end

      database_id_field

      created_at_field
      updated_at_field

      field :uploader, Platform::Objects::User, null: false, description: "User who uploaded the asset"
      def uploader
        Loaders::ActiveRecord.load(::User, @object.user_id)
      end

      field :name, String, null: false, description: "Name of the asset"
      def name
        @object.name
      end

      field :content_type, String, null: false, description: "MIME type of the asset"
      def content_type
        @object.content_type
      end

      field :size, Integer, null: false, description: "Size of the asset in bytes"
      def size
        @object.size
      end

      field :guid, String, null: false, description: "GUID of the asset"
      def guid
        @object.guid
      end

      field :new_format, Boolean, null: false, description: "Whether the asset is using the new URL format"
      def new_format
        @object.using_new_url?
      end
    end
  end
end
