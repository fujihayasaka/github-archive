# typed: false
# frozen_string_literal: true

# Implements the API that Alambic uses for serving or accepting avatar
# uploads through the Alambic storage cluster. Used on GitHub Enterprise only.
#
# https://github.com/github/alambic/tree/master/docs/assets
class Api::Internal::StorageAvatars < Api::Internal::StorageUploadable
  require_api_semantic_version "smasher"

  def self.enforce_private_mode?
    false
  end

  get "/internal/storage/avatars/:id", operation_id: :internal do
    @route_owner = "@github/avatars"
    avatar = ActiveRecord::Base.connected_to(role: :reading) { Avatar.find_by_id(int_id_param!) }

    if avatar&.quarantined?
      deliver_error! 403, message: "Avatar is quarantined"
    end

    control_access :personal_avatar_reader, resource: avatar, avatar: avatar, allow_integrations: false, allow_user_via_granular_actor: false

    avatar.alambic_use_original_filter = params[:orig] == "1"
    avatar.alambic_size_filter = params[:s] || params[:size]

    deliver :internal_avatar_storage_hash, avatar, env: request.env
  end

  post "/internal/storage/avatars", operation_id: :internal do
    @route_owner = "@github/avatars"
    control_access :create_avatar, resource: owner, owner: owner, allow_integrations: false, allow_user_via_granular_actor: false
    validate_uploadable Avatar, meta: { owner: owner }
  end

  post "/internal/storage/avatars/verify", operation_id: :internal do
    @route_owner = "@github/avatars"
    control_access :create_avatar, resource: owner, owner: owner, allow_integrations: false, allow_user_via_granular_actor: false
    create_uploadable Avatar,
      serializer: :internal_avatar_storage_hash,
      meta: { owner: owner }
  end

  def owner
    @owner ||= ActiveRecord::Base.connected_to(role: :reading) { Avatar.owner_for(nil, @asset_meta) }
  end

  def verify_user(meta)
    Avatar.storage_verify_token(@asset_token, meta)
  end
end
