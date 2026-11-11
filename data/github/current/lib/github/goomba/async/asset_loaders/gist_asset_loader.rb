# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async::AssetLoaders
  class GistAssetLoader < AssetLoader
    def initialize(current_user)
      super(current_user)
      @node_src_asset = {}
    end

    def load_node_asset(node)
      uri = asset_uri(node)

      return unless is_uri_valid?(uri)

      # Check if we match the new canonical URL format for User Assets. This URL
      # path takes the form /user-attachments/assets/<guid> - it does not contain
      # the repo NWO or user ID
      new_url = uri.path.match?(/\/user-attachments\/assets\/#{GUID_REGEX}/)

      return unless new_url || uri.path.match?(/\/assets\//)

      asset_guid_match = uri.request_uri.match(GUID_REGEX)
      return unless asset_guid_match
      asset_guid = asset_guid_match.to_s

      asset_user_id = 0
      unless new_url
        # Extract the User ID from the request path
        # We can pre-emptively not add secure tags if these don't match
        # Only applies to old-style URLs
        asset_user_id_match = uri.path.match(/\/assets\/(?<uid>\d+)\/#{GUID_REGEX}/)
        return unless asset_user_id_match
        asset_user_id = asset_user_id_match[:uid].to_i
      end

      Platform::Loaders::ActiveRecord.load(UserAsset, asset_guid, column: :guid).then do |asset|
        next nil unless asset.present?
        next nil if asset.upload_container_type != Gist.name
        next nil unless new_url || asset.user_id == asset_user_id

        @node_src_asset[node["src"]] = asset
        next @node_src_asset
      end
    end

    def is_uri_valid?(uri)
      (uri.host.match?(/#{gist_domain_name}/) || uri.path.match?(/\/#{gist_domain_name}\//)) && super(uri)
    end

    private

    def gist_domain_name
      "gist"
    end
  end
end
