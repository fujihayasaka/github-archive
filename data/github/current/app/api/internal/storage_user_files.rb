# typed: false
# frozen_string_literal: true

# Implements the API that Alambic uses for serving or accepting issue
# attachments through the Alambic storage cluster. Used on GitHub Enterprise
# only.
#
# https://github.com/github/alambic/tree/master/docs/assets
class Api::Internal::StorageUserFiles < Api::Internal::StorageUploadable
  require_api_semantic_version "smasher"

  def self.enforce_private_mode?
    false
  end

  def deliver_user_file(access, file)
    control_access access, resource: file, file: file, repo: file.repository, allow_integrations: false, allow_user_via_granular_actor: false
    deliver :internal_storage_hash, file, env: request.env
  end

  # Alambic hits this API as the first step of the process used to upload an image. Validates that the upload can be performed
  post "/internal/storage/user/:user_id/repository/:repository_id/files", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"
    owner = ActiveRecord::Base.connected_to(role: :reading) { User.find_by_id(params[:user_id].to_i) }
    repo  = ActiveRecord::Base.connected_to(role: :reading) { Repository.find_by_id(params[:repository_id].to_i) }
    control_access :write_user_files, owner: owner, resource: repo, allow_integrations: false, allow_user_via_granular_actor: false
    validate_uploadable UserAsset,
      meta: { repository_id: params[:repository_id] }
  end

  # Alambic hits this API as the final step of the process used to upload an image. If the first step of the process succeeded,
  # and the upload of the file took place, this final step performs the final model creation
  post "/internal/storage/user/:user_id/repository/:repository_id/files/verify", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"
    owner = ActiveRecord::Base.connected_to(role: :reading) { User.find_by_id(params[:user_id].to_i) }
    repo  = ActiveRecord::Base.connected_to(role: :reading) { Repository.find_by_id(params[:repository_id].to_i) }
    control_access :write_user_files, owner: owner, resource: repo, allow_integrations: false, allow_user_via_granular_actor: false
    create_uploadable UserAsset,
      meta: { repository_id: params[:repository_id] }
  end

  # Alambic hits this endpoint when an image need to be downloaded.
  get "/internal/storage/user/:user_id/repository/:repository_id/files/:guid", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"
    file = ActiveRecord::Base.connected_to(role: :reading) { UserAsset.find_by_guid_and_repository_id(params[:guid], params[:repository_id].to_i) }
    deliver_user_file(:read_user_assets, file)
  end

  def verify_user(meta)
    UserAsset.storage_verify_token(@asset_token, meta)
  end

  # Handles legacy enterprise paths in GHE 2.4 and below.
  # https://uploads.ghe.io/github-enterprise-assets/0000/0126/0000/1147/2a517e68-b60f-11e5-817f-de93ec03543a.png
  get "/internal/storage/github-enterprise-assets/:a/:b/:c/:d/:guid", operation_id: :internal do
    if GitHub.enterprise?
      @route_owner = "@github/data-infrastructure"
      file = ActiveRecord::Base.connected_to(role: :reading) { UserAsset.find_by_guid(params[:guid].to_s.split(".").first) }
      if file.nil? || !file.repository.nil?
        # Give back a 404 for deleted images, or anyone trying to hit this endpoint looking for a secured image
        return deliver_error(404)
      end
      deliver_user_file(:read_user_files, file)
    else
      deliver_error(404)
    end
  end

  get "/internal/storage/user/:user_id/files/:guid", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"

    return deliver_error(404) unless GitHub.storage_cluster_enabled?

    if GitHub.storage_cluster_private_assets_enabled?
      return deliver_error(404) unless token_valid?
    end

    file = ActiveRecord::Base.connected_to(role: :reading) { UserAsset.where(guid: params[:guid], user_id: params[:user_id].to_i).first }
    return deliver_error(404) if file.nil?

    control_access :read_upload_container_user_assets,
      resource: file,
      upload_container: file.repository || file.upload_container,
      allow_integrations: false,
      allow_user_via_granular_actor: false
    deliver :internal_storage_hash, file, env: request.env
  end

  post "/internal/storage/user/:user_id/files", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"
    owner = ActiveRecord::Base.connected_to(role: :reading) { User.find_by_id(params[:user_id].to_i) }
    control_access :write_user_files, owner: owner, resource: owner, allow_integrations: false, allow_user_via_granular_actor: false
    validate_uploadable UserAsset
  end

  post "/internal/storage/user/:user_id/files/verify", operation_id: :internal do
    @route_owner = "@github/data-infrastructure"
    owner = ActiveRecord::Base.connected_to(role: :reading) { User.find_by_id(params[:user_id].to_i) }
    control_access :write_user_files, owner: owner, resource: owner, allow_integrations: false, allow_user_via_granular_actor: false
    create_uploadable UserAsset
  end

  private

  def token_valid?
    @current_user_auth&.valid?
  end
end
