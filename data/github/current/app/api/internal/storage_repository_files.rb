# typed: true
# frozen_string_literal: true

# Implements the API that Alambic uses for serving or accepting repository
# files through the Alambic storage cluster. Used on GitHub Enterprise only.
#
# https://github.com/github/alambic/tree/master/docs/assets
class Api::Internal::StorageRepositoryFiles < Api::Internal::StorageUploadable
  require_api_semantic_version "smasher"

  get "/internal/storage/repositories/:repository_id/files/:id", operation_id: :internal do
    @route_owner = Platform::NoOwnerBecause::UNAUDITED
    file = ActiveRecord::Base.connected_to(role: :reading) { RepositoryFile.includes(:storage_blob).find_by(id: params[:id].to_i) }
    file = nil if file.repository_id != params[:repository_id].to_i
    repo = file && file.repository
    control_access :read_repo_file, repo: repo, file: file, allow_integrations: false, allow_user_via_granular_actor: false
    deliver :internal_storage_hash, file, env: request.env
  end

  post "/internal/storage/repositories/:repository_id/files", operation_id: :internal do
    @route_owner = Platform::NoOwnerBecause::UNAUDITED
    repo = ActiveRecord::Base.connected_to(role: :reading) do
      if FeatureFlag.vexi.enabled?(:repos_by_id_api_internal, default: false)
        ::Repositories.domain.by_id(params[:repository_id].to_i)
      else
        Repository.find_by(id: params[:repository_id].to_i)
      end
    end
    control_access :pull_storage, resource: repo, allow_integrations: false, allow_user_via_granular_actor: false
    validate_uploadable RepositoryFile,
      meta: { repository_id: params[:repository_id] },
      repo: repo
  end

  post "/internal/storage/repositories/:repository_id/files/verify", operation_id: :internal do
    @route_owner = Platform::NoOwnerBecause::UNAUDITED
    repo = ActiveRecord::Base.connected_to(role: :reading) do
      if FeatureFlag.vexi.enabled?(:repos_by_id_api_internal, default: false)
        ::Repositories.domain.by_id(params[:repository_id].to_i)
      else
        Repository.find_by(id: params[:repository_id].to_i)
      end
    end
    control_access :pull_storage, resource: repo, allow_integrations: false, allow_user_via_granular_actor: false
    create_uploadable RepositoryFile,
      meta: { repository_id: params[:repository_id] }
  end

  def verify_user(meta)
    RepositoryFile.storage_verify_token(@asset_token, meta)
  end
end
