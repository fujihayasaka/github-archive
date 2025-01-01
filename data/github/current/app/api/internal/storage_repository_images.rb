# typed: false
# frozen_string_literal: true

# Implements the API that Alambic uses for serving or accepting repository
# image uploads through the Alambic storage cluster.
#
# https://github.com/github/alambic/tree/master/docs/assets
class Api::Internal::StorageRepositoryImages < Api::Internal::StorageUploadable
  require_api_semantic_version "smasher"

  def self.enforce_private_mode?
    false
  end

  get "/internal/storage/repository/:id/images/:guid", operation_id: :internal do
    @route_owner = "@github/repos"
    repo = if FeatureFlag.vexi.enabled?(:repos_by_id_api_internal, default: false)
      ::Repositories.domain.by_id(params[:id].to_i)
    else
      Repository.find_by_id(params[:id])
    end
    return deliver_error!(404) unless repo
    if image = repo.repository_images.preload(:storage_blob, :repository).find_by_guid(params[:guid])
      control_access :read_repo_file,
        resource: image,
        repo: repo,
        file: image,
        allow_integrations: false,
        allow_user_via_granular_actor: false

      deliver :internal_storage_hash, image, env: request.env
    else
      deliver_error!(404)
    end
  end

  post "/internal/storage/repository/:id/images", operation_id: :internal do
    @route_owner = "@github/repos"
    repo = ActiveRecord::Base.connected_to(role: :reading) do
      if FeatureFlag.vexi.enabled?(:repos_by_id_api_internal, default: false)
        ::Repositories.domain.by_id(params[:id].to_i)
      else
        Repository.find_by_id(params[:id])
      end
    end
    return deliver_error!(404) unless repo
    control_access :create_repo_image,
      resource: repo,
      allow_user_via_granular_actor: false,
      allow_integrations: false

    validate_uploadable RepositoryImage, repo: repo, meta: { repository_id: params[:id] }
  end

  post "/internal/storage/repository/:id/images/verify", operation_id: :internal do
    @route_owner = "@github/repos"
    repo = ActiveRecord::Base.connected_to(role: :reading) do
      if FeatureFlag.vexi.enabled?(:repos_by_id_api_internal, default: false)
        ::Repositories.domain.by_id(params[:id].to_i)
      else
        Repository.find_by_id(params[:id])
      end
    end
    return deliver_error!(404) unless repo
    control_access :create_repo_image,
      resource: repo,
      allow_user_via_granular_actor: false,
      allow_integrations: false

    create_uploadable RepositoryImage, meta: { repository_id: params[:id] }
  end

  def verify_user(meta)
    RepositoryImage.storage_verify_token(@asset_token, meta)
  end
end
