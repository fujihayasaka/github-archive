# typed: true
# frozen_string_literal: true

# Internal endpoints for the aleph code navigation service
class Api::Internal::Aleph < Api::Internal
  require_api_semantic_version "alephinternalauth"

  get "/internal/aleph/:repo_id/token", operation_id: :internal, resolve_tenant_context: :resolve_tenant_from_repo do
    @route_owner = "@github/blackbird"
    load_repository(params[:repo_id])

    data = {
      proto: "http",
      member: "gitauth-full-trust:aleph",
    }
    expiration = 1.hour.from_now.utc
    token = GitHub::Authentication::GitAuth::SignedAuthToken.generate(
      repo: @current_repo, scope: "read", data: data, expires: expiration,
    )

    deliver_raw(
      {
        id: @current_repo.id,
        network_id: @current_repo.network_id,
        owner: @current_repo.owner_display_login,
        name: @current_repo.name,
        nwo: @current_repo.name_with_display_owner,
        token: token,
        expires_at: expiration.iso8601,
        root_id: @current_repo.network.root_id,
      },
    )
  end

  get "/internal/aleph/:repo_id", operation_id: :internal, resolve_tenant_context: :resolve_tenant_from_repo do
    @route_owner = "@github/blackbird"
    load_repository(params[:repo_id])

    ref = params[:ref] || "refs/heads/#{@current_repo.default_branch}"

    deliver_raw(
      {
        id: @current_repo.id,
        network_id: @current_repo.network_id,
        owner: @current_repo.owner_display_login,
        name: @current_repo.name,
        nwo: @current_repo.name_with_display_owner,
        ref: ref,
        sha: @current_repo.ref_to_sha(ref),
        private: @current_repo.private?,
        default_branch: @current_repo.default_branch,
        disk_usage: @current_repo.disk_usage,
        root_id: @current_repo.network.root_id,
      },
    )
  end

  get "/internal/aleph/:owner/:repo", operation_id: :internal, resolve_tenant_context: :resolve_tenant_from_nwo do
    @route_owner = "@github/blackbird"
    load_repository_nwo(params[:owner], params[:repo])

    ref = params[:ref] || "refs/heads/#{@current_repo.default_branch}"

    deliver_raw(
      {
        id: @current_repo.id,
        network_id: @current_repo.network_id,
        owner: @current_repo.owner_display_login,
        name: @current_repo.name,
        nwo: @current_repo.name_with_display_owner,
        ref: ref,
        sha: @current_repo.ref_to_sha(ref),
        private: @current_repo.private?,
        default_branch: @current_repo.default_branch,
        disk_usage: @current_repo.disk_usage,
        root_id: @current_repo.network.root_id,
      },
    )
  end

  def require_request_hmac?
    true
  end

  def load_repository(repo_id)
    @current_repo = ActiveRecord::Base.connected_to(role: :reading) do
      Repository.find_by(id: repo_id)
    end

    ensure_repository_exists_and_indexing_enabled
  end

  def load_repository_nwo(user, repo)
    if user.blank? || repo.blank?
      deliver_error! 400, message: "repository key is empty"
    end

    repo_name = "#{user}/#{repo}"
    @current_repo = ActiveRecord::Base.connected_to(role: :reading) do
      Repository.with_name_with_owner(repo_name) || RepositoryRedirect.find_redirected_repository(repo_name)
    end

    ensure_repository_exists_and_indexing_enabled
  end

  def ensure_repository_exists_and_indexing_enabled
    if @current_repo.nil?
      deliver_error! 404, message: "repository does not exist"
    end

    if @current_repo.archived?
      deliver_error! 404, message: "repository archived"
    end

    if @current_repo&.owner&.spammy?
      deliver_error! 404, message: "repository owner spammy"
    end
  end

  def resolve_tenant_from_repo
    load_repository(params[:repo_id])
    Business.find_by(id: @current_repo.tenant_id)
  end

  def resolve_tenant_from_nwo
    load_repository_nwo(params[:owner], params[:repo])
    Business.find_by(id: @current_repo.tenant_id)
  end

  def check_allowlist_for_request_limiting
    GitHub::Limiters::Middleware.skip_limit_checks(env)
  end
end
