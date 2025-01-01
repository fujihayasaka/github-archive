# typed: true
# frozen_string_literal: true

class Api::RepositoryCommits < Api::App
  include ReceiveSchemaWithOpenApi
  include FeatureFlagHelper

  include Api::App::DiffContentsDependency

  # List commits on a repo
  get "/repositories/:repository_id/commits", operation_id: "repos/list-commits" do
    begin
      control_access :list_commits,
        resource: repo = find_repo!,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      ensure_repo_content!(repo)

      options = {}
      options[:path] = path_string if params[:path]
      options.merge!(git_log_options)

      if options[:path] && !options[:path].valid_encoding?
        deliver_error! 400
      end

      start_sha = if (s = params[:last_sha]).present?
        options[:skip] = 1
        s
      elsif (s = params[:sha]).present?
        s
      else
        repo.default_branch
      end

      if author = params[:author]
        author_user = User.find_by_login(author) if author =~ User::LOGIN_REGEX || author =~ User::LOGIN_REGEX_FOR_EMUS
        options[:author] = author_user || author
      end

      if committer = params[:committer]
        committer_user = User.find_by_login(committer) if committer =~ User::LOGIN_REGEX || committer =~ User::LOGIN_REGEX_FOR_EMUS
        options[:committer] = committer_user || committer
      end

      if repo.is_enterprise_managed?
        options[:enterprise_managed_business] = repo.enterprise_managed_business
      end

      commits = if paginating_via_legacy_params?
        repo.paged_commits(start_sha, 1, pagination[:per_page], options)
      else
        repo.paged_commits(start_sha, current_page, pagination[:per_page], options)
      end

      commits.compact!

      # Batch-verify signatures.
      Commit.prefill_verified_signature(commits, repo)

      # Add comment counts
      CommitComment.attach_counts_to_commits(commits)

      user_hash = User.find_by_commits(commits, :all, business: repo.enterprise_managed_business)

      if commits.size == pagination[:per_page]
        if paginating_via_legacy_params?
          @links.add_current({
            top: params[:top] ||= start_sha, last_sha: commits.last.sha
          }, rel: "next")
        else
          @links.add_current({ page: current_page + 1 }, rel: "next")
          last_page = calculate_last_page(commits.filters, repo)
          @links.add_current({ page: last_page }, rel: "last") if last_page
        end
      end

      if paginating_via_legacy_params?
        @links.add_current({ top: nil, last_sha: nil, sha: params[:top] }, rel: "first")
      elsif current_page > 1
        @links.add_current({ page: 1 }, rel: "first")
        @links.add_current({ page: current_page - 1 }, rel: "prev")
      end

      serialize_options = {
        repo: repo,
        emails: user_hash,
        global_id_selection: global_id_selection,
      }

      if (mimes = request.accept).present?
        serialize_options[:accept_mime_types] = mimes
      end

      last_modified = calc_last_modified(commits)
      commits.map! do |commit|
        Api::Serializer.serialize(:git_commit_hash, commit, serialize_options)
      end

      deliver_raw commits, last_modified: last_modified
    rescue GitRPC::Timeout => boom
      Failbot.report(boom) unless boom.cached?
      deliver_error! 500
    rescue GitRPC::ObjectMissing
      deliver_error! 404
    rescue GitRPC::CommandFailed, Repository::CommandFailed => boom
      if boom.to_s =~ /bad object/
        deliver_error! 404
      else
        raise
      end
    end
  end

  # Get branch names where that SHA is the HEAD
  get "/repositories/:repository_id/commits/*/branches-where-head", operation_id: "repos/list-branches-for-head-commit" do
    begin
      ref = params[:splat].first
      control_access :get_commit,
        resource: repo = find_repo!,
        allow_integrations: true,
        allow_user_via_granular_actor: true
      ensure_repo_content!(repo)

      commit = find_commit!(repo, ref, @documentation_url)
      deliver_error!(404) unless commit

      sha = commit.sha
      branches_where_head = repo.heads.select { |h| h.target_oid == sha }
      branches_where_head.map! do |head|
        Api::Serializer.serialize(:short_branch_hash, head)
      end
      deliver_raw branches_where_head
    rescue GitRPC::ObjectMissing
      deliver_error! 404
    end
  end

  # Get the associated pull requests for a commit
  get "/repositories/:repository_id/commits/*/pulls", operation_id: "repos/list-pull-requests-associated-with-commit" do
    begin
      repo = find_repo!
      ref = params[:splat].first
      control_access :list_pull_requests, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true
      ensure_repo_content!(repo)

      commit = find_commit!(repo, ref, @documentation_url)
      deliver_error!(404) unless commit

      opts = { current_user: current_user }
      if (mimes = request.accept).present?
        opts[:accept_mime_types] = mimes
      end

      deliver(:associated_pull_requests_hash, commit, opts)
    rescue GitRPC::ObjectMissing
      deliver_error! 404
    end
  end

  # Get commit
  get "/repositories/:repository_id/commits/*", operation_id: "repos/get-commit" do
    # to maintain compatibility with existing 300 file diff that was historically returned
    # we need to override the default paginator
    @paginator = build_paginator(default_per_page: GitHub::Diff::DEFAULT_MAX_FILES, max_per_page: GitHub::Diff::DEFAULT_MAX_FILES)

    delivering_raw_diff_content(medias) do
      ref = params[:splat].first
      control_access :get_commit,
        resource: repo = find_repo!,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      ensure_repo_content!(repo)

      commit = find_commit!(repo, ref, @documentation_url)
      deliver_error!(404) unless commit

      diff = commit.init_diff
      diff.use_summary = true

      delta_index_from = pagination[:per_page] * (pagination[:page] - 1) # Subtract 1 page num since it's 1-indexed
      delta_index_to = (pagination[:per_page] * pagination[:page])
      diff.add_delta_indexes((delta_index_from...delta_index_to).to_a)

      deliver_error!(404) if commit.diff.missing_commits?

      if medias.api_param?(:diff)
        if !commit.diff.available? || commit.diff.truncated_for_timeout?
          deliver_undiffable_error!(:Commit, commit.diff)
        end

        deliver_raw repo.rpc.native_diff_text(commit.oid),
          content_type: "#{medias}; charset=utf-8",
          last_modified: calc_last_modified_for_object(commit)
      elsif medias.api_param?(:patch)
        if !commit.diff.available? || commit.diff.truncated_for_timeout?
          deliver_undiffable_error!(:Commit, commit.diff)
        end

        deliver_raw repo.rpc.native_patch_text(commit.oid),
          content_type: "#{medias}; charset=utf-8",
          last_modified: calc_last_modified_for_object(commit)
      elsif medias.api_param?("sha")
        deliver_raw commit.sha,
          content_type: "#{medias}; charset=utf-8",
          last_modified: calc_last_modified_for_object(commit),
          etag: commit.sha
      else
        # We have a hard limit of 3_000 files in a diff, so we need to stop pagination at that point.
        set_pagination_headers(collection_size: [GitRPC::Diff::DiffTreeParser::MAX_FILES, diff.summary.changed_files].min)

        # Add comment counts
        CommitComment.attach_counts_to_commits([commit])
        deliver :git_commit_hash, commit,
          diff: diff,
          repo: repo,
          last_modified: calc_last_modified_for_object(commit)
      end
    end
  end

  private

  def path_string(extra = nil)
    joined_path(extra) * "/"
  end

  def joined_path(extra = nil)
    path = [params[:path], extra]
    path.flatten!
    path.compact!
    path
  end

  def supported_filters
    %w{since until}
  end

  def git_log_options
    log_options = {}
    params.each do |k, v|
      if supported_filters.include?(k.to_s)
        log_options[k.to_sym] = v
      end
    end
    log_options
  end

  def paginating_via_legacy_params?
    params[:top].present?
  end

  def calculate_last_page(filters, repo)
    filters[:until_date] = filters.delete(:until) if filters[:until]

    total = repo.rpc.filterable_commit_count(**filters)

    (total / per_page.to_f).ceil if total
  rescue GitRPC::InvalidFullOid, GitRPC::Timeout
    nil
  end
end
