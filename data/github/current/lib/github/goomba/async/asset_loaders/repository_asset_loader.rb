# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async::AssetLoaders
  class RepositoryAssetLoader < AssetLoader
    def initialize(entity, current_user)
      super(current_user)
      @node_src_asset = {}
      @entity = entity
    end

    def load_node_asset(node)
      uri = asset_uri(node)

      # Only match on URls that contain assets path
      return unless is_uri_valid?(uri)

      # Check if we match the new canonical URL format for User Assets. This URL
      # path takes the form /user-attachments/assets/<guid> - it does not contain
      # the repo NWO or user ID
      new_url = uri.path.match?(/\A\/user-attachments\/assets\/#{GUID_REGEX}/)

      # only match on "/<user>/<repo>/assets/" or "/user-attachments/assets/"
      # i.e don't match "/user/repo/blob/assets/" or "/user/repo/blah/assets/" (i.e RawFilterImage like urls collision)
      return unless new_url || uri.path.match?(/\A\/[^\/]+\/[^\/]+\/assets\//)

      # Extract the Asset GUID from the request path
      # In production: "#{owner_login}/#{repo_name}/assets/#{user_id}/#{guid}"
      asset_guid_match = uri.request_uri.match(GUID_REGEX)
      return unless asset_guid_match
      asset_guid = asset_guid_match.to_s

      asset_user_id = 0
      asset_nwo_url = ""
      unless new_url
        # Extract the User ID from the request path
        # We can pre-emptively not add secure tags if these don't match
        # Only applies to old-style URLs
        asset_user_id_match = uri.path.match(/\/(?<owner_name>[\w.-]+)\/(?<repo_name>[\w.-]+)\/assets\/(?<uid>\d+)\/#{GUID_REGEX}/)
        return unless asset_user_id_match
        asset_user_id = asset_user_id_match[:uid].to_i

        # Extract the NWO from the request URL path
        # Only applies to old-style URLs
        asset_nwo_url = "#{asset_user_id_match[:owner_name]}/#{asset_user_id_match[:repo_name]}"
      end

      Platform::Loaders::ActiveRecord.load(UserAsset, asset_guid, column: :guid).then do |asset|
        next nil unless asset.present?
        next nil unless new_url || asset.user_id == asset_user_id
        next nil unless asset.repository.present?
        if new_url || asset_nwo_url == T.must(asset.repository).name_with_display_owner
          @node_src_asset[node["src"]] = asset
          next @node_src_asset
        end

        # use a loader to check if the repo has been renamed
        Platform::Loaders::RedirectedRepositoryByNwo.load(asset_nwo_url).then do |renamed_repo|
          next nil unless renamed_repo.present? && renamed_repo.id == asset.repository_id
          @node_src_asset[node["src"]] = asset
          next @node_src_asset
        end
      end
    end

    def log_error(error, attributes = {})
      log = {
        "gh.repo.visibility": repository.public? ? "public" : "private",
        "gh.repo.id": repository.id,
      }

      super(error, log.merge(attributes))
    end

    def build_metric_tags
      tags = super
      tags << "entity_visibility:#{repository.public? ? "public" : "private"}"
      tags << "entity_type:Repository"

      tags
    end

    private

    def repository
      case @entity
      when GitHub::Unsullied::Wiki
        @entity.repository
      when Repository
        @entity
      end
    end
  end
end
