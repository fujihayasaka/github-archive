# typed: true
# frozen_string_literal: true

class Api::Internal::Archive < Api::Internal::GitContent
  # Bypass IP allow list enforcement for public repositories.
  def ip_allowlist_enforceable
    return :no if repo_or_gist.is_a?(Repository) && repo_or_gist.public?
    :yes
  end

  # Request comes from:
  #
  #   https://github.com/{user}/{repo}/archive/{commitish}.{ext}
  #
  get "/internal/archive", operation_id: :internal do
    @route_owner = "@github/repos"
    deliver_error! 404, message: "Missing path parameter" unless params[:path]
    params[:path] = params[:path][1..-1] if params[:path][0] == "/"
    params[:user], params[:repo], params[:arc_type], params[:splat] = params[:path].scrub.split(/\//, 4)
    deliver_error! 404, message: "Bogus path" unless params[:user] && params[:repo] && params[:arc_type] && params[:splat]
    params[:splat] = [params[:splat].gsub(/\/+\Z/, "")]

    @api_stats_key = :archive

    # "gist" isn't a valid username, don't try to use it to find a gist
    attempt_remote_token_login GitRepository::ArchiveCommand.token_scope(repo_or_gist), forbid: true
    verify_not_spammy

    # validate repo_or_gist
    repository_or_gist_or_404 repo_or_gist

    if repo_or_gist.is_a?(Gist)
      control_access :get_gist_contents,
        resource: repo_or_gist,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    else
      control_access :get_contents,
        resource: repo_or_gist,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    end

    deliver_error! 404, message: "Not Found" if params[:token] && anonymous_request?

    # The repo or gist is valid and we would want to serve it. Check whether
    # this has been administratively blocked
    if repo_or_gist.archive_resource_blocked? || (repo_or_gist.is_a?(Repository) && repo_or_gist.network.archive_resource_blocked?)
      deliver_error! 422, message: "Cannot create archives for #{repo_or_gist.name_with_display_owner}"
    end

    if hash = repository_archive_hash(repo_or_gist)
      deliver_raw hash
    else
      deliver_error 404, message: "Bad archive command for #{repo_or_gist.name_with_display_owner}/#{h content_path.inspect}/#{h params[:arc_type].inspect}"
    end
  end

  def repository_archive_hash(repo_or_gist)
    actor_id = logged_in? ? current_user.id : 0
    actor_token = if logged_in? && repo_or_gist.is_a?(Repository)
      current_user.signed_auth_token(expires: 1.hour.from_now,
                                     scope: Media.auth_scope(repo_or_gist.id, "download"))
    else
      nil
    end
    repo_or_gist.archive_command(content_path, params[:arc_type],
                                 actor_id: actor_id,
                                 actor_token: actor_token).to_hash
  rescue ArgumentError
  end

  def gist_owner_param
    :user unless params[:user] == "gist"
  end

  def repo_or_gist
    return @repo_or_gist if defined? @repo_or_gist

    @repo_or_gist = find_repo || find_gist(param_name: :repo, owner_param: gist_owner_param)
  end
end
