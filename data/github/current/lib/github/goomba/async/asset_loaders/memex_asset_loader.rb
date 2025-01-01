# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async::AssetLoaders
  class MemexAssetLoader < AssetLoader
    def initialize(memex_project, current_user)
      super(current_user)
      @node_asset = {}
      @memex_project = memex_project
    end

    def load_node_asset(node)
      uri = asset_uri(node)

      # Only match on URls that contain assets path
      return unless is_uri_valid?(uri)

      # Check if we match the new canonical URL format for User Assets. This URL
      # path takes the form /user-attachments/assets/<guid> - it does not contain
      # the repo NWO or user ID
      new_url = uri.path.match?(/\A\/user-attachments\/assets\/#{GUID_REGEX}/)

      # only match on "/<users|orgs>/<user|org name>/projects/<id>/assets/"
      return unless new_url || uri.path.match?(/\A\/(users|orgs)\/[^\/]+\/projects\/[^\/]+\/assets\//)

      # Extract the Asset GUID from the request path
      # In production: "user-attachments/assets/#{guid}"
      # In production (old-style URLs): "users|orgs/#{org_|user_name}/projects/#{project_id}/assets/#{user_id}/#{guid}"
      asset_guid_match = uri.request_uri.match(GUID_REGEX)
      return unless asset_guid_match
      asset_guid = asset_guid_match.to_s

      project_id = 0
      asset_user_id = 0
      owner_display_name = ""
      unless new_url
        # Extract the User ID, project ID, and owner display name from the request path
        # Only applies for old-style URLs
        asset_user_id_match = uri.path.match(/\A\/(users|orgs)+\/(?<owner_display_name>.+)\/projects\/(?<project_id>\d+)\/assets\/(?<uid>\d+)\/#{GUID_REGEX}/)
        owner_display_name = asset_user_id_match[:owner_display_name]
        project_id = asset_user_id_match[:project_id].to_i
        asset_user_id = asset_user_id_match[:uid].to_i
      end

      Platform::Loaders::ActiveRecord.load(UserAsset, asset_guid, column: :guid).then do |asset|
        next nil unless asset.present?
        next nil unless asset.upload_container.present? && asset.upload_container.is_a?(MemexProject)

        unless new_url
          next nil unless asset.user_id == asset_user_id
          next nil unless asset.upload_container.number == project_id
          next nil unless asset.upload_container.owner_display_name == owner_display_name
        end

        @node_asset[node] = asset
        next @node_asset
      end
    end

    def log_error(error, attributes = {})
      log = {
        "gh.memex.project.is_public": @memex_project.public?,
        "gh.memex.project.id": @memex_project.id,
      }

      super(error, log.merge(attributes))
    end

    def build_metric_tags
      tags = super
      tags << "entity_visibility:#{@memex_project.public? ? "public" : "private"}"
      tags << "entity_type:#{@memex_project.class.name}"

      tags
    end
  end
end
