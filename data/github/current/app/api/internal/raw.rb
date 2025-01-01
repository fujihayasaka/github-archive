# typed: true
# frozen_string_literal: true

class Api::Internal::Raw < Api::Internal::GitContent
  INTERNAL_RAW_COMMIT_OID_REGEX = /\A[a-f0-9]{40}\z/

  # Bypass IP allow list enforcement for public repositories.
  def ip_allowlist_enforceable
    return :no if current_repository&.public?
    :yes
  end

  # Internal API endpoint for raw.githubusercontent.com.  Used to authenticate a raw
  # request.
  #
  #   https://raw.githubusercontent.com/{user}/{repo}/{commitish}/{path}?token={token}
  #
  get "/internal/raw/github", operation_id: :internal do
    # for new stuff, we want to pass all these params via params to avoid
    # path traversal
    @route_owner = "@github/repos"
    populate_legacy_params_from_path_param

    verify_not_spammy

    branch, path = gitrpc { ref_sha_path_extractor.call(content_path) }

    if !branch
      result = gitrpc { RepositoryBranchRename::Detector.call(repository: current_repository, full_path: content_path) }
      if result.includes_renamed_branch?
        branch = result.redirect_branch
        path = result.path
      end
    end

    attempt_remote_token_login RawBlob.scope(current_repository, branch, path), forbid: true

    control_access :get_contents,
      resource: current_repository,
      path: content_path,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if GitHub.flipper[:codeload_reject_invalid_tokens_raw].enabled?(current_repository)
      deliver_error! 404, message: "Not Found" if params[:token] && anonymous_request?
    end

    serve_contents do
      deliver_blob_info(
        current_repository,
        branch,
        content_path,
        file: path,
        geo_block_list: current_repository.access.blocked_countries,
        disable_caching: disable_caching?,
      )
    end
  end

  # Request comes from:
  #
  #   https://raw.githubusercontent.com/wiki/{user}/{repo}/{commitish}/{path}?token={token}
  #
  get "/internal/raw/wiki", operation_id: :internal do
    # for new stuff, we want to pass all these params via params to avoid
    # path traversal
    @route_owner = "@github/repos"
    populate_legacy_params_from_path_param

    verify_wiki_access_allowed
    verify_not_spammy

    attempt_remote_token_login RawBlob.wiki_scope(current_repository, content_path), forbid: true
    control_access :get_contents, resource: current_repository, allow_integrations: false, allow_user_via_granular_actor: false

    wiki = current_repository.unsullied_wiki
    gitrpc { deliver_blob_info(wiki, wiki.default_oid, content_path, prefix: current_repository.id.to_s, nwo: "#{current_repository.name_with_display_owner}.wiki", disable_caching: disable_caching?) }
  end

  # Request comes from:
  #
  #   https://gist.githubusercontent.com/{user}/{gist}/raw/{sha}/{filename}
  get "/internal/raw/gist", operation_id: :internal do
    # for new stuff, we want to pass all these params via params to avoid
    # path traversal
    @route_owner = "@github/repos"
    populate_legacy_params_from_path_param

    verify_not_spammy

    parts = content_path.split("/")

    # Shift raw off of the parts list, this is from legacy
    # compat with the existing gist raw url structure
    parts.shift if parts.first == "raw"

    commit_oid = if parts.first =~ INTERNAL_RAW_COMMIT_OID_REGEX
      parts.shift
    end

    if parts.first =~ INTERNAL_RAW_COMMIT_OID_REGEX
      parts.shift
    end

    # "raw" isn't a valid username, don't try to use it to find a gist
    owner_param = :user unless params[:user] == "raw"
    gist = find_gist!(param_name: :gist, owner_param: owner_param)
    path = parts.join("/")
    attempt_remote_token_login RawBlob.gist_scope(gist, commit_oid || gist.sha, path), forbid: true

    gitrpc do
      blob_oid = gist.retrieve_blob_oid_for_path(path, commit_oid)
      deliver_blob_info gist, nil, content_path, commit: blob_oid, file: path
    end
  end

  def deliver_blob_info(routable, commitish = nil, content_path = nil, hash = {})
    hash[:file] ||= content_path
    hash[:commit] ||= begin
                        if commitish
                          # If we don't know our commit OID, we will look it up, but prefer to
                          # find a branch rather than a tag because the web UI is biased
                          # towards branches, rather than the ref lookup rules, that bias
                          # toward finding tags first.
                          # See:
                          #  https://www.kernel.org/pub/software/scm/git/docs/git-rev-parse.html
                          #  https://github.com/github/github/issues/40473
                          commit_oid ||= (
                            routable.rev_parse("refs/heads/#{commitish}") ||
                            routable.rev_parse("#{commitish}^{}")
                          )
                        end
                        if !commit_oid
                          return deliver_error 404, message: "bad branch: #{h commitish.inspect}"
                        end

                        routable.gist_blob_oid_by_path(hash[:file], commit_oid)
                      end

    hash[:routes] ||= routable.dgit_read_routes.map do |route|
      { "route" => route.resolved_host, "path" => route.path }
    end
    hash[:route] ||= routable.route
    hash[:path] ||= routable.shard_path
    hash[:prefix] ||= "#{routable}"
    hash[:type] ||= "raw"
    hash[:mime_type] ||= begin
                           # routable should include TreeListable
                           if routable.respond_to?(:blob_by_oid)
                             blob = routable.blob_by_oid(hash[:commit], full_blob: false)
                             raw_mime_for(content_path, is_text: blob.text?)
                           else
                             raw_mime_for(content_path)
                           end
                         end
    hash[:nwo] ||= routable.name_with_display_owner

    # Currently, codeload uses the disable_caching key to determine whether to set the Cache-Control header to
    # "private" or not.  This key is used to set the Cache-Control max-age based on whether the content is
    # public or not when caching is enabled.
    hash[:is_public_commit] = false

    if routable.feature_enabled?(:codeload_public_commit)
      if routable.respond_to?(:public?)
        hash[:is_public_commit] = routable.public? && !is_branch_or_symref?(content_path, commitish)
      end
    end

    deliver_raw hash
  end

  def populate_legacy_params_from_path_param
    deliver_error! 404, message: "Missing path parameter" unless params[:path]
    params[:path] = params[:path][1..-1] if params[:path][0] == "/"
    params[:user], params[:repo], params[:splat] = params[:path].scrub.split(/\//, 3)
    deliver_error! 404, message: "Bogus path" unless params[:user] && params[:repo]
    params[:splat] = if params[:splat]
      [params[:splat].gsub(/\/+\Z/, "")]
    else
      []
    end
    params[:gist] = params[:repo]
  end

  def disable_caching?
    # This needs to be defined as narrowly as possible so that we get good
    # cache performance from fastly.  We _do_ want to skip caching when IP
    # allowlists are enabled so that we can revalidate each client that's
    # trying to get a file.
    return false if current_repository.public?
    return false unless current_repository.owner&.organization?
    return true if current_repository.owner&.business&.idp_based_ip_allowlist_configuration?
    current_repository.owner.ip_allowlist_enabled? || current_repository.owner.ip_allowlist_enabled_policy?
  end

  def is_branch_or_symref?(path, commitish)
    # Checks whether the path contains a branch name or a symref (HEAD), which we use to determine whether a different
    # TTL should be set for this file when it is cached.  Since gists don't pass a commitish to deliver_blob_info,
    # we'll have this check return true and maintain normal caching behavior for gist raw files.
    return true unless commitish

    branch = path.split("/").first
    ref_sha_path_extractor.symref?(branch) || !ref_sha_path_extractor.looks_like_an_oid?(commitish)
  end
end
