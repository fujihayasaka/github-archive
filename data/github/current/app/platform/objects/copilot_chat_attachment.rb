# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CopilotChatAttachment < Platform::Objects::Base
      model_name "::Copilot::ChatAttachment"
      description "An internal object for getting a user copilot chat attachments's URL"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      visibility :internal, environments: [:dotcom]

      minimum_accepted_scopes ["site_admin"]

      implements_node templates: [[:cca, :uploader_id, :signed_url, :id]], as: "CCA", ready_date: "1970-01-01" do |chat_attachment|
        {
          prefix: :cca,
          uploader_id: chat_attachment.uploader_id,
          signed_url: chat_attachment.redirect_url(expiration: 24.hours.seconds),
          id: chat_attachment.id,
        }
      end

      database_id_field

      field :name, String, "The name of the attachment.", null: false
      field :uploader_id, Integer, "The ID of the user who uploaded the attachment.", null: false
      field :size, Integer, "The size of the attachment in bytes.", null: false
      field :content_type, String, "The content type of the attachment.", null: false
      field :state, Enums::StorageState, "The state of the attachment.", null: false
      def state
        T.must(Enums::StorageState.values[@object.state.upcase]).value
      end

      field :url, Scalars::URI, "The attachments's URL to render it.", null: false
      def url
        @object.permalink
      end

      field :signed_url, Scalars::URI, "The attachments's URL to render it.", null: false do
        argument :expiration, Integer, "Presigned URL expiration.", required: false
      end
      def signed_url(expiration: 24.hours.seconds)
        @object.redirect_url(expiration: expiration)
      end
    end
  end
end
