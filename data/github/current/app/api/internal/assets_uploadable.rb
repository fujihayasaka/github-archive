# typed: true
# frozen_string_literal: true

# Superclass for AssetsMedia, AssetsAvatars, etc
class Api::Internal::AssetsUploadable < Api::Internal

  def grab_metadata
    data = verify_and_receive(Hash, required: false) || {}

    @asset_meta = {}
    @asset_oid = data["oid"].to_s
    @asset_token = token_from_data(data)

    ASSET_ATTRIBUTE_STR.each_with_index do |key, index|
      next unless value = data[key]
      @asset_meta[ASSET_ATTRIBUTES[index]] = value
    end
  end

  def token_from_data(data)
    token = Api::RequestCredentials.token_from_scheme(env, "remoteauth")

    token || (params["token"] || data["token"]).to_s
  end

  def attempt_login
    @current_user = nil
    grab_metadata
    login_from_api_auth
    login_with_remote_auth unless @current_user
  end

  def login_with_remote_auth
    return if @asset_token.blank?
    login_user_for_remote_auth(@asset_token, @asset_meta)
  end

  def login_user_for_remote_auth(token, scope_hash)
    auth = verify_user(token, scope_hash)
    if !auth.user
      log_data[:signed_auth_token_failure] = auth.reason
    end

    @current_user_auth = auth
    @current_user = auth.user
  end

  def verify_user(asset_token, scope)
    raise NotImplementedError
  end

  def default_content_type
    "application/vnd.github.smasher+json; charset=utf-8"
  end

  def storage_path_info
    @storage_path_info ||= env["PATH_INFO"].chomp("/verify").sub(%r{\A/internal/assets/}, "/internal/storage/")
  end

  def s3_storage_path_info
    @s3_storage_path_info ||= env["PATH_INFO"].delete_prefix("/internal/assets/user/auth/")
  end

  ASSET_ATTRIBUTES = [:name, :content_type, :size, :directory, :original_type, :original_size, :organization_id, :upload_url, :owner_type, :owner_id] + Asset::ACCEPTED_METADATA
  ASSET_ATTRIBUTE_STR = ASSET_ATTRIBUTES.map { |a| a.to_s }
end
