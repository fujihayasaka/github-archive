# typed: false
# frozen_string_literal: true

# Superclass for AssetsMedia, AssetsAvatars, etc
class Api::Internal::StorageUploadable < Api::Internal

  def self.enforce_private_mode?
    true
  end

  def validate_uploadable(uploadable_class, serializer: nil, meta: {}, repo: nil, key: nil)
    if !GitHub.storage_cluster_enabled?
      deliver_error! 500, message: "Storage Cluster is not configured."
    end

    meta = @asset_meta.merge(meta)
    blob = Storage::Blob.new(oid: meta[:oid], size: meta[:size])
    uploadable = uploadable_class.storage_new(current_user, blob, meta)
    if repo && uploadable.respond_to?(:repository=)
      uploadable.repository = repo
    end

    if !uploadable.valid?
      deliver_error! 422, errors: uploadable.errors
    end

    serializer ||= :internal_storage_validation_hash
    uploadable.storage_cluster_upload_source_url = @asset_meta[:upload_url]
    deliver serializer, uploadable, status: 202, repo: repo, public_key: key
  end

  def create_uploadable(uploadable_class, serializer: nil, meta: {})
    if !GitHub.storage_cluster_enabled?
      deliver_error! 500, message: "Storage Cluster is not configured."
    end

    meta = @asset_meta.merge(meta)
    creator_params = meta.slice(:oid, :size)
    creator_params[:host_urls] = Array(meta[:replicas]).map { |r| r["url"] }
    uploadable = GitHub::Storage::Creator.perform(**creator_params) do |blob|
      uploadable_class.storage_create(current_user, blob, meta)
    end

    if uploadable.nil?
      deliver_error! 422, errors: []
    end

    serializer ||= :internal_storage_hash
    deliver serializer, uploadable, status: 201, current_user: current_user, env: request.env

  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => err
    deliver_error 422, errors: err.record.errors
  end

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

  def enforce_private_mode?
    self.class.enforce_private_mode? && GitHub.private_mode_enabled?
  end

  def attempt_login
    @current_user = nil
    grab_metadata
    login_from_api_auth
    login_with_remote_auth unless @current_user

    if !@current_user && !@authenticated_key && enforce_private_mode?
      deliver_error! 403, message: "Must authenticate to access this API."
    end
  end

  # This lets us skip private mode enforcement for storage things that are
  # accessible publicly: Avatars, Issue Attachments (called User Files in the
  # code).
  def authenticated_for_private_mode?
    return true unless self.class.enforce_private_mode?
    super
  end

  def login_with_remote_auth
    return if @asset_token.blank?

    auth = verify_user(@asset_meta.merge(path_info: storage_path_info))
    if !auth.valid?
      log_data[:signed_auth_token_failure] = auth.reason
    end

    @current_user_auth = auth
    @current_user = auth.user
    @remote_token_auth = auth.valid?
    @authenticated_key = auth.respond_to?(:public_key) ? auth.public_key : nil
  end

  def storage_path_info
    @storage_path_info ||= env["PATH_INFO"].to_s.chomp("/verify").to_s
  end

  def verify_user(meta)
    raise NotImplementedError
  end

  def default_content_type
    "application/vnd.github.smasher+json; charset=utf-8"
  end

  ASSET_ATTRIBUTES = [
    :name,
    :content_type,
    :size,
    :directory,
    :label,
    :original_type,
    :original_size,
    :upload_url,
    :replicas,
    :oid,
    :repository_type,
    :repository_id,
    :owner_type,
    :owner_id,
    :application_id,
    :full_path,
    :business_id,
    :bytes_transferred_down,
    :enterprise_installation_id,
    :upload_container_type,
    :upload_container_id] + Asset::ACCEPTED_METADATA
  ASSET_ATTRIBUTE_STR = ASSET_ATTRIBUTES.map { |a| a.to_s }
end
