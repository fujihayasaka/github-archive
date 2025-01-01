# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async::AssetLoaders
  class SavedReplyAssetLoader < AssetLoader
    def initialize(current_user)
      super(current_user)
      @node_asset = {}
    end

    def load_node_asset(node)
      uri = asset_uri(node)

      # Only match on URls that contain assets path
      return unless is_uri_valid?(uri)

      # Check if we match the new canonical URL format for User Assets. This URL
      # path takes the form /user-attachments/assets/<guid> - it does not contain
      # the repo NWO or user ID
      new_url = uri.path.match?(/\A\/user-attachments\/assets\/#{GUID_REGEX}/)

      # only match on "/settings/replies/assets/"
      return unless new_url || uri.path.start_with?("/settings/replies/assets")

      # Extract the Asset GUID from the request path
      # In production: "user-attachments/assets/#{guid}"
      # In production (legacy URL format): "settings/replies/assets/#{user_id}/#{guid}"
      asset_guid_match = uri.request_uri.match(GUID_REGEX)
      return unless asset_guid_match
      asset_guid = asset_guid_match.to_s

      asset_user_id = 0
      unless new_url
        # Extract the user ID from the request path
        # Only for old-style URLs
        asset_user_id_match = uri.path.match(/\A\/settings\/replies\/assets\/(?<uid>\d+)\/#{GUID_REGEX}/)[:uid]
        asset_user_id = asset_user_id_match.to_i
      end

      Platform::Loaders::ActiveRecord.load(UserAsset, asset_guid, column: :guid).then do |asset|
        next nil unless asset.present?
        next nil unless asset.upload_container.present? && asset.upload_container.is_a?(User)

        unless new_url
          next nil unless asset.user_id == asset_user_id
          next nil unless asset.upload_container.id == asset_user_id
        end

        @node_asset[node] = asset
        next @node_asset
      end
    end

    def build_metric_tags
      tags = super
      tags << "entity_visibility:private"
      tags << "entity_type:#{User.name}"

      tags
    end
  end
end
