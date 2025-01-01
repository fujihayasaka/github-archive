# typed: true
# frozen_string_literal: true

# Implements the API that Alambic uses for serving or accepting release
# files through the Alambic storage cluster. Used on GitHub Enterprise only.
#
# https://github.com/github/alambic/tree/master/docs/assets
class Api::Internal::StorageReleaseFiles < Api::Internal::StorageUploadable
  require_api_semantic_version "smasher"

  get "/internal/storage/releases/:release_id/files/:id", operation_id: :internal do
    @route_owner = "@github/releases"
    file = ActiveRecord::Base.connected_to(role: :reading) { Releases::Public.load_asset(params[:id].to_i) }
    if file.release_id != params[:release_id].to_i
      file = nil
    end

    repo = file && file.repository
    control_access :get_release, repo: repo, resource: file.release, allow_integrations: true, allow_user_via_granular_actor: false
    deliver :internal_storage_hash, file, env: request.env
  end

  # Handles legacy enterprise paths in GHE 2.4 and below.
  # https://uploads.ghe.io/github-enterprise-releases/0000/0446/15f48ed4-a029-11e5-9684-f4b5d0771f04.png?filename=graph-1.png
  get "/internal/storage/github-enterprise-releases/:release_id_1/:release_id_2/:guid", operation_id: :internal do
    # This replicates GHE 2.4 behavior, where any release is accessible if
    # you know the release ID and release file GUID. No user auth necessary.
    # They used to be served by nginx.
    @route_owner = "@github/releases"
    deliver_error!(404) unless GitHub.enterprise?

    rel_id = "#{params[:release_id_1]}#{params[:release_id_2]}".to_i
    rel = ActiveRecord::Base.connected_to(role: :reading) do
      Releases::Public.load_release(rel_id)
    end
    file = rel && rel.release_assets.find_by_guid(params[:guid].to_s.split(".").first)
    deliver :internal_storage_hash, file, env: request.env
  end

  post "/internal/storage/releases/:release_id/files", operation_id: :internal do
    @route_owner = "@github/releases"
    release = ActiveRecord::Base.connected_to(role: :reading) do
      Releases::Public.load_release(params[:release_id].to_i)
    end
    repo = release && release.repository
    control_access :edit_release, repo: repo, resource: release, allow_integrations: true, allow_user_via_granular_actor: false
    validate_uploadable ReleaseAsset,
      meta: { release_id: params[:release_id] },
      repo: repo
  end

  post "/internal/storage/releases/:release_id/files/verify", operation_id: :internal do
    @route_owner = "@github/releases"
    release = ActiveRecord::Base.connected_to(role: :reading) do
      Releases::Public.load_release(params[:release_id].to_i)
    end
    repo = release && release.repository
    control_access :edit_release, repo: repo, resource: release, allow_integrations: true, allow_user_via_granular_actor: false
    create_uploadable ReleaseAsset,
      meta: { release_id: params[:release_id] }
  end

  def verify_user(meta)
    Releases::Public.storage_interface.storage_verify_token(@asset_token, meta)
  end
end
