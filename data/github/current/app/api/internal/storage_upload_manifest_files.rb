# typed: true
# frozen_string_literal: true

# Implements the API that Alambic uses for serving or accepting upload
# manifest files through the Alambic storage cluster. Used on GitHub Enterprise
# only.
#
# https://github.com/github/alambic/tree/master/docs/assets
class Api::Internal::StorageUploadManifestFiles < Api::Internal::StorageUploadable
  require_api_semantic_version "smasher"

  get "/internal/storage/upload-manifest-files/:upload_manifest_id/files/:id", operation_id: :internal do
    @route_owner = Platform::NoOwnerBecause::UNAUDITED
    file = ActiveRecord::Base.connected_to(role: :reading) { UploadManifestFile.where(id: params[:id], upload_manifest_id: params[:upload_manifest_id]).includes(:storage_blob).first }
    repo = ActiveRecord::Base.connected_to(role: :reading) { UploadManifest.includes(:repository).find_by(id: params[:upload_manifest_id]).try(:repository) }
    deliver_error!(404) unless file
    control_access :pull_storage, resource: repo, allow_integrations: false, allow_user_via_granular_actor: false
    deliver :internal_storage_hash, file, env: request.env
  end

  post "/internal/storage/upload-manifest-files/:upload_manifest_id/files", operation_id: :internal do
    @route_owner = Platform::NoOwnerBecause::UNAUDITED
    repo = ActiveRecord::Base.connected_to(role: :reading) { UploadManifest.includes(:repository).find_by(id: params[:upload_manifest_id]).try(:repository) }
    control_access :pull_storage, resource: repo, allow_integrations: false, allow_user_via_granular_actor: false
    validate_uploadable UploadManifestFile,
      meta: { upload_manifest_id: params[:upload_manifest_id], repository_id: repo.id },
      repo: repo
  end

  post "/internal/storage/upload-manifest-files/:upload_manifest_id/files/verify", operation_id: :internal do
    @route_owner = Platform::NoOwnerBecause::UNAUDITED
    repo = ActiveRecord::Base.connected_to(role: :reading) { UploadManifest.includes(:repository).find_by(id: params[:upload_manifest_id]).try(:repository) }
    control_access :pull_storage, resource: repo, allow_integrations: false, allow_user_via_granular_actor: false
    create_uploadable UploadManifestFile,
      meta: { upload_manifest_id: params[:upload_manifest_id], repository_id: repo.id }
  end

  def verify_user(meta)
    UploadManifestFile.storage_verify_token(@asset_token, meta)
  end
end
