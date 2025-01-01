# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async::AssetLoaders
  class GHESLegacyAssetLoader < AssetLoader
    ASSET_URL_PATTERN = %r{\/user\/(?<user_id>\d+)\/files\/(?<guid>#{GUID_REGEX})}

    def initialize(current_user)
      super(current_user)
      @node_asset = {}
    end

    def is_uri_valid?(uri)
      uri.present? && uri.host.present? && uri.host.match?(/#{storage_cluster_url_host}/) && uri.request_uri != "/"
    end

    def load_node_asset(node)
      uri = asset_uri(node)

      return unless is_uri_valid?(uri)
      return unless uri.path.match?(ASSET_URL_PATTERN)

      path_matches = uri.path.match(ASSET_URL_PATTERN)
      asset_user_id = path_matches[:user_id].to_i
      asset_guid = path_matches[:guid]


      Platform::Loaders::ActiveRecord.load(UserAsset, asset_guid, column: :guid).then do |asset|
        next nil unless asset.present?
        next nil unless asset.user_id == asset_user_id

        @node_asset[node] = asset
        next @node_asset
      end
    end

    private

    def storage_cluster_url_host
      Addressable::URI.parse(GitHub.storage_cluster_url).host
    end
  end
end
