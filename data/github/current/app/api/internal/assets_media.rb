# typed: true
# frozen_string_literal: true

# Implements the API that Alambic uses for serving LFS objects through the
# GitHub Raw feature.
class Api::Internal::AssetsMedia < Api::Internal::AssetsUploadable

  include Api::App::ContentHelpers
  include RawBlob::ContentHelpers

  require_api_semantic_version "smasher"

  get "/internal/assets/media/:user/:repo/?*", operation_id: :internal do
    @route_owner = "@github/repos"
    branch, path = ref_sha_path_extractor.call(content_path)
    verify_auth_token(branch, path)

    control_access :get_media_blob, repo: current_repo, allow_integrations: false, allow_user_via_granular_actor: false

    unless branch && path
      deliver_error!(404,
        message: "invalid ref from #{GitHub::JSON.encode content_path}")
    end

    blob = gitrpc do
      sha = current_repo.ref_to_sha(branch)
      tree_entry = sha.present? && current_repo.blob(sha, path)
      tree_entry && tree_entry.git_lfs? && ActiveRecord::Base.connected_to(role: :reading) { ::Media::Blob.fetch(current_repo, tree_entry.git_lfs_oid) }
    end

    if blob.try(:viewable?)
      blob.path = path
      deliver(:internal_media_asset_hash, blob,
        max_age: max_age_from_token,
        origin: env["HTTP_ORIGIN"],
        repo: current_repo,
        status: 200,
        user: current_user)
    else
      deliver_error(404)
    end
  end

  def verify_user(asset_token, meta)
    result = User.verify_signed_auth_token(token: asset_token, scope: Media::Blob.auth_scope(meta))
    @remote_token_auth = result.valid?
    result
  end

  def find_repo
    @current_repo ||= Repository.nwo(params[:user].to_s, params[:repo].to_s)
  end

  def max_age_from_token
    RawBlob.max_age_from(@current_user_auth, fallback: 5.minutes)
  end

  def verify_auth_token(branch, path)
    scope = ::Media::Blob.auth_scope_options(current_repo, branch, path)
    login_user_for_remote_auth @asset_token, scope

    if GitHub.private_mode_enabled? && !logged_in?
      deliver_error! 403, message: "Must authenticate to access this API."
    end
  end

  # We'll handle private mode by enforcing a ?token.  #current_user is not set
  # yet because we need to parse out the branch and path for the remote auth
  # scope.
  def protect_access_to_enterprise_hosts
  end

  # we'll just have to live as an anon user until #verify_auth_token is called.
  def login_with_remote_auth
  end
end
