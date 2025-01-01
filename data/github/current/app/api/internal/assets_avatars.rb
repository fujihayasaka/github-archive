# typed: false
# frozen_string_literal: true

# Implements the API that Alambic uses for serving or accepting avatar
# uploads through the Alambic service. Used on GitHub.com only.
#
# https://github.com/github/alambic/tree/master/docs/assets
class Api::Internal::AssetsAvatars < Api::Internal::AssetsUploadable
  require_api_semantic_version "smasher"

  get "/internal/assets/user/:user_id/avatars/:id", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"
    avatar = ActiveRecord::Base.connected_to(role: :reading) { Avatar.find_by_id(int_id_param!) }

    if avatar&.quarantined?
      deliver_error! 403, message: "Avatar is quarantined"
    end

    control_access :read_avatar, owner_type: "User",
     owner_id: params[:user_id], avatar: avatar, resource: avatar,
     allow_integrations: false, allow_user_via_granular_actor: false

    avatar.alambic_use_original_filter = params[:orig] == "1"
    avatar.alambic_size_filter = params[:s] || params[:size]

    deliver :internal_avatar_asset_hash, avatar
  end

  get "/internal/assets/avatars/:id", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"
    avatar = ActiveRecord::Base.connected_to(role: :reading) { Avatar.find_by_id(int_id_param!) }

    if avatar&.quarantined?
      deliver_error! 403, message: "Avatar is quarantined"
    end

    control_access :personal_avatar_reader,
      avatar: avatar,
      resource: avatar,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    avatar.alambic_use_original_filter = params[:orig] == "1"
    avatar.alambic_size_filter = params[:s] || params[:size]
    deliver :internal_avatar_asset_hash, avatar
  end

  post "/internal/assets/avatars", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"
    control_access :create_avatar, resource: owner, owner: owner, allow_integrations: false, allow_user_via_granular_actor: false

    begin
      avatar = Avatar.validate_asset(current_user, @asset_meta)
      return deliver_error 422, errors: avatar.errors unless avatar.valid?

      body = { path_prefix: avatar.alambic_path_prefix }
      filters = avatar.alambic_upload_filters
      body[:filters] = filters if filters

      deliver_raw body, status: 202
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => err
      deliver_error 422, errors: err.record.errors
    end
  end

  post "/internal/assets/avatars/verify", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"
    control_access :create_avatar, resource: owner, owner: owner, allow_integrations: false, allow_user_via_granular_actor: false

    begin
      avatar = Avatar.upload(current_user, @asset_oid, @asset_meta)

      deliver :internal_avatar_hash, avatar, status: 201
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => err
      deliver_error 422, errors: err.record.errors
    end
  end

  def owner
    @owner ||= ActiveRecord::Base.connected_to(role: :reading) { Avatar.owner_for(nil, @asset_meta) }
  end

  def verify_user(asset_token, meta)
    Avatar.storage_verify_token(asset_token, meta.merge(path_info: storage_path_info))
  end
end
