# typed: false
# frozen_string_literal: true

# Implements the API that the CDN uses to authenticate the requests
# before serving them. Used on GitHub.com only.

class Api::Internal::AssetsAuth < Api::Internal::AssetsUploadable

  require_api_semantic_version "smasher"

  get "/internal/assets/user/auth/:user_id/:guid", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"
    # The :guid parameter follows the pattern "#{@user_asset.id}-#{@user_asset.guid}.file_extension"
    file = ActiveRecord::Base.connected_to(role: :reading) { UserAsset.find_by_guid(params[:guid].split(".")[0].split("-", 2)[1]) }
    control_access :read_user_assets, resource: file, file: file, repo: file.try(:repository), allow_integrations: false, allow_user_via_granular_actor: false
  end

  def verify_user(asset_token, meta)
    UserAsset.storage_verify_token(@asset_token, meta.merge(path_info: s3_storage_path_info))
  end
end
