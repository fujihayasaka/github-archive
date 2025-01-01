# typed: false
# frozen_string_literal: true

# Implements the API that Alambic uses for serving or accepting avatar
# uploads through the Alambic storage cluster. Used on GitHub Enterprise only.
#
# https://github.com/github/alambic/tree/master/docs/assets
class Api::Internal::StorageOauthApplicationLogos < Api::Internal::StorageUploadable
  require_api_semantic_version "smasher"

  def self.enforce_private_mode?
    false
  end

  get "/internal/storage/oauth_logos/:guid", operation_id: :internal do
    @route_owner = "@github/avatars"
    logo = ActiveRecord::Base.connected_to(role: :reading) { OauthApplicationLogo.includes(:storage_blob).find_by_guid(params[:guid].to_s) }
    control_access :read_user_files, resource: logo, file: logo, allow_integrations: false, allow_user_via_granular_actor: false
    deliver :internal_storage_hash, logo, env: request.env
  end

  post "/internal/storage/oauth_logos", operation_id: :internal do
    @route_owner = "@github/avatars"
    control_access :write_oauth_app_logo, resource: current_user, allow_integrations: false, allow_user_via_granular_actor: false
    validate_uploadable OauthApplicationLogo
  end

  post "/internal/storage/oauth_logos/verify", operation_id: :internal do
    @route_owner = "@github/avatars"
    control_access :write_oauth_app_logo, resource: current_user, allow_integrations: false, allow_user_via_granular_actor: false
    create_uploadable OauthApplicationLogo
  end

  def verify_user(meta)
    OauthApplicationLogo.storage_verify_token(@asset_token, meta)
  end
end
