# typed: true
# frozen_string_literal: true

# Implements the API that Alambic uses for serving or accepting LFS object
# uploads through the Alambic storage cluster. Used on GitHub Enterprise only.
#
# https://github.com/github/alambic/tree/master/docs/assets
class Api::Internal::StorageLfs < Api::Internal::StorageUploadable
  require_api_semantic_version "smasher"

  get "/internal/storage/lfs/:repository_id/objects/:oid", operation_id: :internal do
    @route_owner = "@github/lfs"
    repo = if FeatureFlag.vexi.enabled?(:repos_by_id_api_internal, default: false)
      ::Repositories.domain.by_id(params[:repository_id].to_i)
    else
      Repository.find_by(id: params[:repository_id])
    end
    control_access :get_media_blob, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true
    blob = repo && ActiveRecord::Base.connected_to(role: :reading) { Media::Blob.find_by(repository_network_id: repo.network_id, oid: params[:oid]) }
    blob = nil unless blob.verified?

    if blob && blob.viewable?
      deliver :internal_storage_hash, blob, env: request.env
    else
      deliver_error(404)
    end
  end

  post "/internal/storage/lfs/:repository_id/objects/:oid", operation_id: :internal do
    @route_owner = "@github/lfs"
    repo = if FeatureFlag.vexi.enabled?(:repos_by_id_api_internal, default: false)
      ::Repositories.domain.by_id(params[:repository_id].to_i)
    else
      Repository.find_by(id: params[:repository_id])
    end
    control_access :create_media_blob, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true
    validate_uploadable Media::Blob,
      meta: { network_id: T.must(repo).network_id, oid: params[:oid] },
      repo: repo, key: @authenticated_key
  end

  post "/internal/storage/lfs/:repository_id/objects/:oid/verify", operation_id: :internal do
    @route_owner = "@github/lfs"
    repo = if FeatureFlag.vexi.enabled?(:repos_by_id_api_internal, default: false)
      ::Repositories.domain.by_id(params[:repository_id].to_i)
    else
      Repository.find_by(id: params[:repository_id])
    end
    control_access :create_media_blob, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true
    create_lfs meta: { oid: params[:oid], repo: repo }
  end

  def verify_user(meta)
    Media::Blob.storage_verify_token(@asset_token, meta)
  end

  # Similar to StorageUploadable#create_uploadable
  # LFS objects are initialized by the batch API, so they don't need to be
  # inserted again.
  def create_lfs(meta: {})
    if !GitHub.storage_cluster_enabled?
      deliver_error! 500, message: "Storage Cluster is not configured."
    end

    hosts = Array(@asset_meta[:replicas]).map { |r| r["url"] }
    consensus = GitHub::Storage::ClusterConsensus.new(hosts)
    if !consensus.reached?
      deliver_error! 422, errors: [] # TODO need the right error for this
    end

    uploadable = T.let(nil, T.nilable(Media::Blob))

    Storage::Blob.transaction do
      uploadable = Media::Blob.fetch(meta[:repo], meta[:oid])
      meta = @asset_meta.merge(meta)

      uploadable.update!(
        storage_blob: Storage::Blob.create_for_uploadable(meta),
        state: :verified,
      )

      Storage::Replica.create_for_uploadable(uploadable, hosts: consensus.replicated_hosts)
    end

    deliver :internal_storage_hash, uploadable, status: 201, env: request.env

  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => err
    deliver_error 422, errors: err.record.errors
  end
end
