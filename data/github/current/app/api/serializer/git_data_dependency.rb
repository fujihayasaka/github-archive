# typed: true
# frozen_string_literal: true

module Api::Serializer::GitDataDependency
  extend T::Helpers

  requires_ancestor { T.class_of(Api::Serializer) }

  # Creates an Array of Hashes for each commit.  Pulls comment counts and author
  # data efficiently in batches.
  #
  # commits - Array of Commit objects.
  # options - Hash
  #           :repo   - Repositories instance that this commit belongs to.
  def commits_array(commits, options = {})
    return [] if commits.blank?

    options = Api::SerializerOptions.from(options)

    total_commits = commits.count

    if options.page
      commits = commits.paginate(per_page: options.per_page, page: options.page)
    end

    commit_hashes_array(
      total_commits: total_commits,
      commits: commits,
      options: options
    )
  end

  def commit_hashes_array(total_commits:, commits:, options: {})
    return [] if commits.blank?

    options = Api::SerializerOptions.from(options)

    commit_repo = commits.first.repository # gets the head repository

    counts_hash = if commit_repo
      commit_ids = commits.map(&:oid)
      commit_repo.commit_comments.where(commit_id: commit_ids).filter_spam_for(options[:current_user]).group(:commit_id).count
    else
      {}
    end

    options.repo ||= commit_repo

    business = options.repo.enterprise_managed_business if options.repo&.is_enterprise_managed?
    user_hash = User.find_by_commits(commits, :all, business: business)

    options.emails = user_hash
    options.comment_counts = counts_hash

    Commit.prefill_verified_signature(commits, options.repo)

    commit_hashes = commits.map do |commit|
      git_commit_hash(commit, options)
    end

    if options.page
      collection = WillPaginate::Collection.new(options.page, options.per_page, total_commits)
      commit_hashes = collection.replace(commit_hashes)
    end

    commit_hashes
  end

  # Creates a Hash for a commit to be serialized to JSON. This is only used
  # within non-commit responses. The commit_hash method is used for the main
  # commit representation.
  #
  # commit - Commit instance.
  # options - Hash
  #           :repo   - Repositories instance that this commit belongs to.
  #           :emails - Hash of String email mapping to a User instance.
  #           :comment_counts - Hash of String commit to Integer comment counts.
  #
  # Returns a Hash if the git Commit exists, or nil.
  def git_commit_hash(commit, options = {})
    return nil if !commit

    options = Api::SerializerOptions.from(options)

    repo_path = repo_path(options, commit)
    repo = options.repo || commit.repository

    author = {
      name: commit.author_name,
      email: commit.author_email,
      date: time(commit.authored_date),
    }
    committer = {
      name: commit.committer_name,
      email: commit.committer_email,
      date: time(commit.committed_date),
    }
    tree = {
      sha: commit.tree_oid,
      url: url("/repos/#{repo_path}/git/trees/#{commit.tree_oid}"),
    }

    parents = commit.parent_oids.map do |parent_oid|
      {
        sha: parent_oid,
        url: url("/repos/#{repo_path}/commits/#{parent_oid}"),
        html_url: html_url("/#{repo_path}/commit/#{parent_oid}"),
      }
    end

    emails = options.emails || {}
    counts = options.comment_counts || {}
    comment_count = counts[commit.oid] || commit.comment_count
    hash = {
      sha: commit.oid,
      node_id: global_id_for(commit, options),
      commit: {
        author: author,
        committer: committer,
        message: commit.message,
        tree: tree,
        url: url("/repos/#{repo_path}/git/commits/#{commit.oid}"),
        comment_count: comment_count.to_i,
        verification: verification_hash(commit),
      },
      url: url("/repos/#{repo_path}/commits/#{commit.oid}"),
      html_url: html_url("/#{repo_path}/commit/#{commit.oid}"),
      comments_url: url("/repos/#{repo_path}/commits/#{commit.oid}/comments"),
      author: user_hash_by_email(commit.author_email, emails, content_options(options), repo),
      committer: user_hash_by_email(commit.committer_email, emails, content_options(options), repo),
      parents: parents,
    }

    if diff = options[:diff]
      hash[:stats] = {
        total: diff.changes,
        additions: diff.additions,
        deletions: diff.deletions,
      }
      hash[:files] = []

      diff.to_a.each do |entry|
        hash[:files] << condensed_diff_entry_hash(entry, options)
      end
    end

    hash
  end

  def user_hash_by_email(email_or_record, cache = nil, options = {}, repo)
    email = (email_or_record.try(:email) || email_or_record).to_s
    return {} if email.blank?

    # If the repo belongs to an Enterprise Managed business,
    # we need to pass the business to the lookup to append the business shortcode to the email.
    # If the repo does not belong to an Enterprise Managed business,
    # the business passed is nil and the lookup by email will behave as normal.
    user = (cache && cache[email]) || User.find_by_email(email, business: repo&.enterprise_managed_business)
    user_hash(user, content_options(options))
  end

  # Creates a Hash to be serialized to JSON.
  #
  # blob    - TreeEntry
  # options - Hash
  #
  # Returns a Hash if the Blob exists, or nil.
  def grit_blob_hash(blob, options = {})
    options = Api::SerializerOptions.from(options)
    repo = repo_path(options, blob)
    return nil if !blob

    {
      sha: blob.oid,
      node_id: global_id_for(blob, options),
      size: blob.size,
      url: url("/repos/#{repo}/git/blobs/#{blob.oid}"),
      content: encode_base64(blob.raw_data, stats_key: "git_blob"),
      encoding: "base64",
    }
  end

  def commit_hash(commit, options = {})
    options = Api::SerializerOptions.from(options)
    repo_url = options.repo.permalink
    repo = repo_path(options, commit)
    parents = commit.parent_oids.map do |p|
      {
        sha: p,
        url: url("/repos/#{repo}/git/commits/#{p}"),
        html_url: "#{repo_url}/commit/#{p}",
      }
    end
    hash = {
      sha: commit.oid,
      node_id: global_id_for(commit, options),
      url: url("/repos/#{repo}/git/commits/#{commit.oid}"),
      html_url: "#{repo_url}/commit/#{commit.oid}",
      author: {
        name: commit.author_name,
        email: commit.author_email,
        date: time(commit.authored_date),
      },
      committer: {
        name: commit.committer_name,
        email: commit.committer_email,
        date: time(commit.committed_date),
      },
      tree: {
          sha: commit.tree_oid,
          url: url("/repos/#{repo}/git/trees/#{commit.tree_oid}"),
      },
      message: commit.message,
      parents: parents,
      verification: verification_hash(commit),
    }

    hash
  end

  def tag_hash(tag, options = {})
    options = Api::SerializerOptions.from(options)
    repo = repo_path(options, tag)

    # Some older versions of Git do not require a tagger; we have
    # a few imported repositories that cause errors due to that if
    # we don't do this:
    tagger_info = if tag.author_name.blank?
      # TODO In API v4, return null values here instead of empty strings.
      #      By using empty strings here, our JSON schema is forced to define
      #      `email` and `date` as string attributes. If we instead returned
      #      null values here, then our JSON schema could properly define
      #      `email` as a nullable email attribute and `date` as a nullable
      #      datetime attribute.
      { name: "", email: "", date: "" }
    else
      {
        name: tag.author_name,
        email: tag.author_email,
        date: time(tag.authored_date),
      }
    end

    # Jamming these together to maintain APIv3 compatibility. In APIv4, the
    # tag message and the tag signature should probably be returned in separate
    # fields.
    message_including_signature =
      if tag.has_signature?
        tag.message + tag.signature
      else
        tag.message
      end

    hash = {
      node_id: global_id_for(tag, options),
      sha: tag.oid,
      url: url("/repos/#{repo}/git/tags/#{tag.oid}"),
      tagger: tagger_info,
      object: {
        sha: tag.target_oid,
        type: tag.target_type,
        url: url("/repos/#{repo}/git/#{tag.target_type}s/#{tag.target_oid}"),
      },
      tag: tag.name,
      message: message_including_signature,
      verification: verification_hash(tag),
    }

    hash
  end

  def api_git_trees_tree_hash(tree, options = {})
    options = Api::SerializerOptions.from(options)
    repo = repo_path(options, tree)
    tarr = tree.entries.map do |entry|
      hash = {
        path: entry.path,
        mode: entry.mode.rjust(6, "0"),
        type: entry.type,
        sha: entry.oid,
      }

      if entry.blob?
        hash.update(size: entry.size)
      end

      unless entry.submodule?
        hash.update(url: url("/repos/#{repo}/git/#{entry.type}s/#{entry.oid}"))
      end

      hash
    end

    {
      sha: tree.sha,
      url: url("/repos/#{repo}/git/trees/#{tree.sha}"),
      tree: tarr,
      truncated: tree.truncated,
    }
  end

  def ref_hash(ref, options = {})
    options = Api::SerializerOptions.from(options)
    repo = repo_path(options, ref)

    {
      ref: ref.qualified_name,
      node_id: global_id_for(ref, options),
      url: url("/repos/#{Api::LegacyEncode.encode(repo)}/git/#{Api::LegacyEncode.encode(ref.qualified_name)}"),
      object: {
        sha: ref.target.oid,
        type: ref.target.class.to_s.downcase,
        url: url("/repos/#{Api::LegacyEncode.encode(repo)}/git/#{ref.target.class.to_s.downcase}s/#{ref.target.oid}"),
      },
    }
  end

  def grit_git_ruby_user_info(object, options = {})
    {
      name: object.name,
      email: object.email,
      date: time(object.date),
    }
  end

  def associated_pull_requests_hash(commit, options = {})
    options = Api::SerializerOptions.from(options)
    current_user = options[:current_user]

    pulls = commit.async_associated_pull_requests(order_by: {}, viewer: current_user).sync
    pulls.map do |pull|
      pull_request_hash(pull, options)
    end
  end

  def branch_hash(ref, options = {})
    raise ArgumentError, "Ref must be a branch" unless ref.branch?

    options = Api::SerializerOptions.from(options)

    {
      name: ref.name,
      commit: git_commit_hash(ref.target, options),
      _links: {
        self: url("/repos/#{ref.repository.name_with_owner_for_api(use: options[:serialize_login])}/branches/#{ref.name}", options),
        html: "#{ref.repository.permalink}/tree/#{ref.name}",
      },
    }
  end

  def branch_with_protection_hash(ref, options = {})
    branch_hash(ref, options).merge({
      protected: ref.protected?,
      protection: branch_protection_hash(ref, options),
      protection_url: url(protected_branch_base_path(ref, options), options),
    })
  end

  # Internal: Return the appropriate payload for a branch's protection (deprecated)
  #
  # ref - the Ref (must be a branch)
  # options - unused, but the other hash methods take one
  #
  # Returns a Hash
  def branch_protection_hash(ref, options = {})
    if protected_branch = ref.protected_branch
      {
        enabled: true,
        required_status_checks: {
          enforcement_level: protected_branch.required_status_checks_enforcement_level,
          contexts: protected_branch.required_status_checks.map(&:context),
          checks: protected_branch.required_status_checks.map do |check|
            { context: check.context, app_id: check.integration_id }
          end,
        },
      }
    else
      {
        enabled: false,
        required_status_checks: {
          enforcement_level: "off",
          contexts: [],
          checks: [],
        },
      }
    end
  end

  def protected_branch_hash(ref, options = {})
    protected_branch = ref.protected_branch
    options = Api::SerializerOptions.from(options)

    hash = {
      url: url(protected_branch_base_path(ref, options), options),
    }

    if protected_branch.required_status_checks_enabled?
      hash[:required_status_checks] = protected_branch_required_status_checks_hash(ref, options)
    end

    if protected_branch.repository.in_organization? && protected_branch.authorized_actors_only?
      hash[:restrictions] = protected_branch_restrictions_hash(ref, options)
    end

    if protected_branch.pull_request_reviews_enabled?
      hash[:required_pull_request_reviews] = protected_branch_pull_request_reviews_hash(ref, options)
    end

    hash[:required_signatures] = protected_branch_required_signatures_hash(ref, options)
    hash[:enforce_admins] = protected_branch_admin_enforced_hash(ref, options)
    hash[:required_linear_history] = protected_branch_required_linear_history_hash(ref, options)
    hash[:allow_force_pushes] = protected_branch_allow_force_pushes_hash(ref, options)
    hash[:allow_deletions] = protected_branch_allow_deletions_hash(ref, options)
    hash[:block_creations] = protected_branch_block_creations_hash(ref, options)
    hash[:required_conversation_resolution] = protected_branch_required_review_thread_resolution_hash(ref, options)
    hash[:lock_branch] = protected_branch_lock_branch_hash(ref, options)
    hash[:allow_fork_syncing] = protected_branch_allow_fork_syncing_hash(ref, options)
    hash
  end

  def protected_branch_required_status_checks_hash(ref, options = {})
    protected_branch = ref.protected_branch

    {
      url: url("#{protected_branch_base_path(ref, options)}/required_status_checks", options),
      strict: protected_branch.strict_required_status_checks_policy?,
      contexts: protected_branch.required_status_checks.map(&:context),
      contexts_url: url("#{protected_branch_base_path(ref, options)}/required_status_checks/contexts", options),
      checks: protected_branch.required_status_checks.map do |check|
        { context: check.context, app_id: check.integration_id }
      end,
    }
  end

  def protected_branch_restrictions_hash(ref, options = {})
    protected_branch = ref.protected_branch
    integrations = protected_branch.authorized_integrations.includes([:owner, :bot, :latest_version])

    {
      url: url("#{protected_branch_base_path(ref, options)}/restrictions", options),
      users_url: url("#{protected_branch_base_path(ref, options)}/restrictions/users", options),
      teams_url: url("#{protected_branch_base_path(ref, options)}/restrictions/teams", options),
      apps_url: url("#{protected_branch_base_path(ref, options)}/restrictions/apps", options),
      users: protected_branch.authorized_users.map { |user| simple_user_hash(user, content_options(options)) },
      teams: protected_branch.authorized_teams.map { |team| team_hash(team, options) },
      apps: integrations.map { |integration| integration_hash(integration, options) },
    }
  end

  def dismissal_restrictions_hash(ref, options = {})
    protected_branch = ref.protected_branch

    hash = {
      url: url("#{protected_branch_base_path(ref, options)}/dismissal_restrictions", options),
      users_url: url("#{protected_branch_base_path(ref, options)}/dismissal_restrictions/users", options),
      teams_url: url("#{protected_branch_base_path(ref, options)}/dismissal_restrictions/teams", options),
      users: protected_branch.dismissal_restricted_users.map { |user| simple_user_hash(user, content_options(options)) },
      teams: protected_branch.dismissal_restricted_teams.map { |team| team_hash(team, options) },
      apps: protected_branch.dismissal_restricted_integration_installations.map do
        |integration_installation| integration_hash(integration_installation.integration, options)
      end
    }

    hash
  end

  def branch_actor_allowance_hash(policy, ref, options = {})
    protected_branch = ref.protected_branch

    hash = {
      users: protected_branch.branch_actor_allowance_users(policy).map { |user| simple_user_hash(user, content_options(options)) },
      teams: protected_branch.branch_actor_allowance_teams(policy).map { |team| team_hash(team, options) },
      apps: protected_branch.branch_actor_allowance_integration_installations(policy).map do |integration_installation|
        integration_hash(integration_installation.integration, options)
      end,
    }

    hash
  end

  def protected_branch_pull_request_reviews_hash(ref, options = {})
    protected_branch = ref.protected_branch
    options = Api::SerializerOptions.from(options)

    hash = {
      url: url("#{protected_branch_base_path(ref, options)}/required_pull_request_reviews", options),
      dismiss_stale_reviews: protected_branch.dismiss_stale_reviews_on_push?,
      require_code_owner_reviews: protected_branch.require_code_owner_review?,
    }

    hash[:require_last_push_approval] = protected_branch.require_last_push_approval?

    hash[:required_approving_review_count] = protected_branch.required_approving_review_count

    if protected_branch.restricted_dismissed_reviews?
      hash[:dismissal_restrictions] = dismissal_restrictions_hash(ref, options)
    end

    if protected_branch.branch_actor_allowance_has_any?(:pull_request)
      hash[:bypass_pull_request_allowances] = branch_actor_allowance_hash(:pull_request, ref, options)
    end

    hash
  end

  def protected_branch_required_signatures_hash(ref, options = {})
    protected_branch = ref.protected_branch

    {
      url: url("#{protected_branch_base_path(ref, options)}/required_signatures", options),
      enabled: protected_branch.required_signatures_enabled?,
    }
  end

  def protected_branch_required_linear_history_hash(ref, options = {})
    protected_branch = ref.protected_branch

    {
      enabled: protected_branch.required_linear_history_enabled?,
    }
  end

  def protected_branch_required_review_thread_resolution_hash(ref, options = {})
    protected_branch = ref.protected_branch

    {
      enabled: protected_branch.required_review_thread_resolution_enabled?,
    }
  end

  def protected_branch_allow_force_pushes_hash(ref, options = {})
    protected_branch = ref.protected_branch

    {
      enabled: !protected_branch.block_force_pushes_enabled? || protected_branch.branch_actor_allowance_has_any?(:force_push)
    }
  end

  def protected_branch_allow_deletions_hash(ref, options = {})
    protected_branch = ref.protected_branch

    {
      enabled: !protected_branch.block_deletions_enabled?,
    }
  end

  def protected_branch_block_creations_hash(ref, options = {})
    protected_branch = ref.protected_branch

    {
      enabled: protected_branch.create_protected_enabled?,
    }
  end

  def protected_branch_admin_enforced_hash(ref, options = {})
    protected_branch = ref.protected_branch

    {
      url: url("#{protected_branch_base_path(ref, options)}/enforce_admins", options),
      enabled: protected_branch.admin_enforced?,
    }
  end

  def protected_branch_lock_branch_hash(ref, options = {})
    protected_branch = ref.protected_branch

    {
      enabled: protected_branch.lock_branch_enabled?,
    }
  end

  def protected_branch_allow_fork_syncing_hash(ref, options = {})
    protected_branch = ref.protected_branch

    # The value expected here is dependent on whether a lock is enabled
    {
      enabled: protected_branch.lock_branch_enabled? && protected_branch.lock_allows_fetch_and_merge?,
    }
  end

  def protected_branch_base_path(ref_or_protected_branch, options = {})
    "/repos/#{ref_or_protected_branch.repository.name_with_owner_for_api(use: options[:serialize_login])}/branches/#{ref_or_protected_branch.name}/protection"
  end
end
