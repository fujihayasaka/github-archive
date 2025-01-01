# typed: false
# frozen_string_literal: true

require "gh/interfaces/default_branch"

module Repository::RefsDependency
  include GH::Interfaces::DefaultBranch

  # Public: Retrieve a repository's branch and tag refs.
  #
  # Returns a Git::Ref::Collection object for accessing Ref objects.
  sig { returns(Git::Ref::Collection) }
  def refs
    return @refs if defined?(@refs)
    @refs = Git::Ref::Collection.new(loader: refs_loader("default"))
  end

  # Public: Retrieve all user-visible refs in the repository including those outside
  # of the heads and tags namespaces. This can be fairly expensive on
  # repositories with many pull requests since special refs are used to maintain
  # the pull request's head and merge info.
  #
  # Returns a Git::Ref::Collection object for accessing Ref objects.
  def extended_refs(prefix = nil)
    return @extended_refs[prefix] if defined?(@extended_refs)

    @extended_refs = Hash.new do |hash, key|
      hash[key] = Git::Ref::Collection.new(loader: refs_loader("extended"), prefix: key)
    end

    @extended_refs[prefix]
  end

  # Public: Returns limited list heads
  # Returns an Array of Git::Ref objects.
  def limited_heads(limit)
    heads
      .lazy
      .sort_by { _1.name == default_branch ? 0 : 1 }
      .take(limit)
  end

  # Public: Retrieve all refs in the repository. This can be fairly expensive on
  # repositories with many pull requests since special refs are used to maintain
  # the pull request's head and merge info.
  #
  # Returns a Git::Ref::Collection object for accessing Ref objects.
  def all_refs
    return @all_refs if defined?(@all_refs)
    @all_refs = Git::Ref::Collection.new(loader: refs_loader)
  end

  # Public: Retrieve a ref collection for all branch refs in the repository.
  #
  # Returns a Git::Ref::Collection object with the prefix set to "refs/heads/".
  sig { returns(Git::Ref::Collection) }
  def heads
    return @heads if defined?(@heads)
    @heads = Git::Ref::Collection.new(loader: refs_loader("default"), prefix: "refs/heads/")
  end

  # Public: Retrieve a ref collection for all internal refs in the repository.
  #
  # Returns a Git::Ref::Collection object with the prefix set to "refs/__gh__/".
  def internal_refs
    return @internal_refs if defined?(@internal_refs)
    @internal_refs = Git::Ref::Collection.new(loader: refs_loader, prefix: "refs/__gh__/")
  end

  # Public: Retrieve a tag collection for all tag refs in the repository.
  #
  # Returns a Git::Ref::Collection object with the prefix set to "refs/tags/".
  sig { returns(Git::Ref::Collection) }
  def tags
    return @tags if defined?(@tags)
    @tags = Git::Ref::Collection.new(loader: refs_loader("default"), prefix: "refs/tags/", order: :desc)
  end

  # Public: Retrieve a tag collection sorted in chronological order for
  # all tag refs in the repository.
  #
  # Returns a Git::Ref::Collection object with the prefix set to "refs/tags/".
  def sorted_tags(pattern: nil)
    @sorted_tags ||= {}

    return @sorted_tags[pattern] if @sorted_tags.key?(pattern)

    @sorted_tags[pattern] = Git::Ref::Collection.new(
      loader: Git::Tag::SortedLoader.new(self, pattern:),
      prefix: "refs/tags/",
      order: :desc,
      branch_sort: false,
    )
  end

  private def refs_loader(read_refs_filter = nil)
    return @refs_loader[read_refs_filter] if defined?(@refs_loader)

    @refs_loader = Hash.new do |hash, key|
      hash[key] = Git::Ref::Loader.new(self, key)
    end

    @refs_loader[read_refs_filter]
  end

  # Public: Clear the refs caches. This forces a fetch of refs hash data from
  # the repository on disk the next time #refs or #extended_refs is accessed by
  # any process. Also forces subsequent Spokes API requests for this repository
  # to not use any cached responses.
  #
  # This should be called any time a ref is modified to make the change visible
  # to other processes. You typically don't need to worry about this if you're
  # using Ref#update since the refs cache is automatically cleared.
  #
  # Returns nothing.
  def clear_ref_cache
    return if network.nil? # bail out if network no longer exists, can't get rpc

    rpc.clear_repository_reference_key!
    reset_refs
    spokes_api_context.read_after_write = true
  end

  # Public: Manually sets the cache key for the gitrpc cache. This allows
  # us to use the checksum passed back from a reference update to set the
  # cache key, rather than getting it from the database.
  #
  # This is useful in the case where we are making a reference update with
  # a transaction in Rails.
  def set_ref_cache_key(checksum)
    return if network.nil?
    return if checksum.nil?

    rpc.set_repository_reference_key!(checksum)
  end

  # Public: Reset the memoized refs data. This forces a fetch of the refs hash
  # from memcached the next time #refs or #extended_refs is accessed.
  #
  # Returns nothing.
  def reset_refs
    remove_instance_variable(:@refs) if defined?(@refs)
    remove_instance_variable(:@all_refs) if defined?(@all_refs)
    remove_instance_variable(:@extended_refs) if defined?(@extended_refs)
    remove_instance_variable(:@heads) if defined?(@heads)
    remove_instance_variable(:@tags) if defined?(@tags)
    remove_instance_variable(:@sorted_tags) if defined?(@sorted_tags)
    remove_instance_variable(:@refs_loader) if defined?(@refs_loader)
    remove_instance_variable(:@default_oid) if defined?(@default_oid)

    # this really shouldn't be necessary but the GitRPC::Client object in
    # development and test environments holds a reference to the
    # Rugged::Repository used to get refs which keeps a cache once read.
    @rpc = nil
  end

  def default_branch_ref
    async_default_branch_ref.sync
  end

  def async_default_branch_ref
    async_default_branch.then do |default_branch|
      heads.async_find(default_branch)
    end
  end

  # Public: The repository's default branch name. This is configured in the
  # repository's admin section. It's set initially based on the owner's
  # preferred default branch name. It's shown by default on the repository's tree
  # homepage. It's also used by the graphs and other subsystems.
  #
  # Returns the string default branch name for this repository.
  def default_branch
    @default_branch ||= begin
      with_database_error_fallback(fallback: nil) do
        refname = self.get_default_branch
        if refname.starts_with?("refs/heads/")
          refname = refname["refs/heads/".length..-1]
        end
        refname.force_encoding("UTF-8")
      end
    rescue SpokesAPI::ResourceExhausted
      # request was rate limited
      raise
    rescue GitRPC::InvalidRepository, SpokesAPI::NotFound => e
      owner_default_new_repo_branch
    rescue GitRPC::RepositoryOffline, GitRPC::ConnectionError, Repository::RpcDependency::UnroutedError, GitHub::DGit::UnroutedError => e
      Failbot.report!(e, app: "github-unrouted")
      owner_default_new_repo_branch
    rescue GitRPC::Error, SpokesAPI::Error => e
      Failbot.report!(e)
      owner_default_new_repo_branch
    end
    if !@default_branch
      owner_default_new_repo_branch
    else
      @default_branch
    end
  end

  def async_default_branch
    async_network.then do
      default_branch
    end
  end

  # Public: Change the repository's default branch.
  def default_branch=(val)
    update_default_branch(val)
  end

  # Public: Check whether the default branch exists.
  #
  # Returns true if a default branch is set and it exists.
  def default_branch_exists?
    default_branch && heads.include?(default_branch)
  end

  # Public: Check whether a branch exists.
  #
  # Returns true if a branch exists.
  def branch_exists?(branch_to_check)
    refs.find(branch_to_check)&.branch?
  end

  # Public: Repository supports protected branches (unlike Unsullied::Wiki and Gist)
  def async_supports_protected_branches?
    self.async_plan_customer.then do
      @supports_protected_branches = self.plan_supports?(:protected_branches)
    end
  end

  # Public: Repository supports protected branches (unlike Unsullied::Wiki and Gist)
  def supports_protected_branches?
    return @supports_protected_branches if defined? @supports_protected_branches

    @supports_protected_branches = self.plan_supports?(:protected_branches)
  end

  # for testing, we change the plan and need to update the @supports_protected_branches
  def plan=(new_plan)
    owner.plan = new_plan
    @supports_protected_branches = self.plan_supports?(:protected_branches)
  end

  # Public: Update the default branch, while holding the dgit lock.
  #
  # new_value - The new default branch name.
  #
  # Returns a Hash with the status of the 3pc transaction.
  def update_default_branch_spokes(new_value)
    use_spokesd = GitHub.spokesd_enabled?
    if use_spokesd
      delegate = repository.dgit_delegate_for_update_refs_coordinator
      tpc = GitHub::DGit::SpokesdThreePhaseCommitClient.new(repository.full_name, delegate)
      result = tpc.update_default_branch(new_value)

      # Symbolic refs are also held in the ref cache, so we need to clear it after updating them.
      self.clear_ref_cache
      self.set_ref_cache_key(result[:checksum])
    else
      # dgit-update does not deal with symrefs, so we perform the lock
      # here manually
      result = GitHub::DGit.with_dgit_lock(self) do
        rpc.update_symbolic_ref("HEAD", new_value)
      end.tap { reset_memoized_attributes }
    end
    result
  end

  # Public: Get a list of branch refs that are reasonable candidates for opening pull requests.
  #
  # Returns an Array of Git::Refs.
  def branch_refs_for_compare
    refs = heads.refs_with_default_first
    branches_to_exclude = branches_being_renamed
    refs.reject do |ref|
      branches_to_exclude.include?(ref.name)
    end
  end

  # Public: Can the given actor switch the default branch?
  #
  # Returns Boolean
  def can_switch_default_branch?(actor)
    branch_renameable_by?(actor, branch: default_branch)
  end

  # Public: Switch the repository's default branch.
  #
  # actor - Actor performing the change
  # branch - Branch name string like "master", "topic", etc.
  #
  # Returns Boolean - true if the branch was changed, falsey otherwise
  def switch_default_branch(actor, new_branch)
    return false unless can_switch_default_branch?(actor)

    update_default_branch(new_branch)
  end

  # Public: Change the repository's default branch (DEPRECATED: use switch_default_branch instead).
  #
  # new_branch - Branch name string like "master", "topic", etc.
  #
  # Returns Boolean - true if the branch was changed, falsey otherwise
  def update_default_branch(new_branch, raise_on_failure: false)
    old_branch = default_branch
    if new_branch&.starts_with?("refs/heads/")
      GitHub.dogstats.increment("repository.default_branch_starts_with_refs_heads")
      return false
    end
    if raise_on_failure
      point_to_new_default_branch!(new_branch)
    else
      return false unless point_to_new_default_branch(new_branch)
    end
    return false unless update_indexes_to_new_default_branch(old_branch, new_branch)
    refresh_workflows if GitHub.actions_enabled? && actions_app_installed?
    MergeQueues.reconcile_queues_and_rulesets!(self) if merge_queue_enabled?
    true
  end

  def point_to_new_default_branch(branch)
    point_to_new_default_branch!(branch)
    true
  rescue Repository::FailedDefaultBranchUpdateError
    false
  end

  def point_to_new_default_branch!(branch)
    old_branch = default_branch
    raise Repository::FailedDefaultBranchUpdateError unless heads.exist?(branch)

    raise Repository::FailedDefaultBranchUpdateError if old_branch == branch

    raise Repository::FailedDefaultBranchUpdateError if branch_being_renamed?(branch)

    new_ref = "refs/heads/#{branch}"
    update_default_branch_spokes(new_ref)
    # Update memoized value
    @default_branch = branch
  end

  def update_indexes_to_new_default_branch(old_branch, branch)
    new_ref = "refs/heads/#{branch}"
    instrument_search_default_branch_update new_ref
    Search.add_to_search_index("code", self.id, "purge" => true)
    Search.add_to_search_index("commit", self.id, "purge" => true)

    enqueue_set_license_job

    RepositoryDependencyRedetectJob.perform_later(id, trigger: :RESET_TRIGGER_DEFAULT_BRANCH_CHANGED)
    if (default_ref_update = refs.detect { |(ref_name, _before, _after)| ref_name == new_ref })
      _refname, _before_oid, after_oid = default_ref_update
      RepositoryCheckPreferredFilesJob.perform_later(self.id, after_oid)
    end

    CommitContribution.backfill(self, true, wait: 1.minute)
    instrument_default_branch_update old: old_branch, branch: default_branch
    true
  end

  # Public: Determine the optimal base branch for a given branch in the current
  # repository. This is used primarily for comparisons when a head branch is given
  # without a base branch.
  #
  #   branch              - The String branch name to find an optimal base for.
  #   user                - The user whose access controls the parent repository's visibility.
  #   include_remote_repo - Optionally include the repository name in the returned string.
  #   repo_seperator      - Optionally include the separator to use between user/repo_name.
  #
  # Returns a String extended ref describing the optimal base commit. The ref
  # may include a ':' in which case the ref exists in a different user
  # repository.
  def base_branch(branch, user, include_remote_repo: false, repo_seperator: "/")
    if can_compare_against_parent?(user)
      if parent.heads.include?(branch)
        return "#{parent.owner.display_login}#{repo_seperator}#{parent.name}:#{branch}" if include_remote_repo
        "#{parent.owner.display_login}:#{branch}"
      elsif parent.default_branch
        return "#{parent.owner.display_login}#{repo_seperator}#{parent.name}:#{parent.default_branch}" if include_remote_repo
        "#{parent.owner.display_login}:#{parent.default_branch}"
      else
        default_branch
      end
    elsif branch == "gh-pages"
      "gh-pages"
    else
      default_branch
    end
  end

  # Public: given a user, determines if that user is able to open a PR against
  # this repo's parent.
  #
  # Handles caching for repeated calls
  def can_compare_against_parent?(user)
    @base_branch_parent_check ||= {}

    key = user && user.id
    return @base_branch_parent_check[key] if @base_branch_parent_check.include?(key)

    @base_branch_parent_check[key] = parent &&
        (matches_parent_visibility? || internal_fork?) &&
        parent.pullable_by?(user)
  end

  # Internal: Determine if this repo and its parent have the same visibility.
  def matches_parent_visibility?
    parent && parent.visibility == self.visibility
  end

  # Public: Given a ref, short sha, or sha, returns the 40 character sha it
  # points to. No network operation is performed when a 40 char SHA1 is
  # provided. Otherwise, the local ref cache is consulted before falling back
  # on a call to git-rev-parse.
  #
  # >> @repo.ref_to_sha('master')
  # => "38e5f93b6b419f5ffff620572c19a0c35799f5fd"
  #
  # >> @repo.ref_to_sha('master2')
  # => nil
  #
  # Returns a string oid or nil.
  def async_ref_to_sha(name)
    return Promise.resolve(nil) if name.nil? || !GitRPC::Util.sanitary_revspec?(name)

    # TODO: push this call further down
    async_network.then do
      refs.async_find(name).then do |ref|
        next ref.commit.oid if ref && ref.commit?
        # check this after looking the ref up in case the ref just has a name that looks like an OID
        next name if SpokesAPI.valid_oid?(name)

        begin
          spokes_api.resolve_object(object_name: name)
        rescue SpokesAPI::NotFound, SpokesAPI::InvalidArgument => boom
          # These errors are definnitely caused by the client, and should be ignored.
          nil
        rescue SpokesAPI::Error => boom
          # These errors are probably caused by the client, but we don't yet
          # handle git's error output correctly in GitRPCd. Ignore these for
          # now.
          nil
        end
      end
    end
  end

  def ref_to_sha(name)
    with_database_error_fallback(fallback: nil) do
      async_ref_to_sha(name).sync
    end
  rescue GitRPC::Timeout
    nil
  end

  # The Git object ID of the commit pointed to by the default branch.
  # May return nil if a repository has no default branch (e.g. freshly created empty repository)
  def default_oid
    with_database_error_fallback(fallback: nil) do
      default_branch_ref&.target_oid
    end
  end

  # Public: update the default branch if the current one does not exist but
  # others do.
  def adjust_default_branch
    default_exists = !heads.find(default_branch).nil?

    return if default_exists

    new_default_branch = heads.names.first
    update_default_branch(new_default_branch)
  end

  # should be called whenever a ref gets deleted,
  # probably always by the PostReceive job.
  def ref_deleted(ref, pusher_id = nil)
    if ref == "refs/heads/#{default_branch}"
      # they removed the default branch so we have to pick a new one
      # to not break everything. anything but the current default.
      new_default_branch = (heads.names - [default_branch]).first
      update_default_branch(new_default_branch)
    end
  end

  def handle_pages_branch_delete(ref)
    if ref == "refs/heads/#{pages_branch}" && page
      # deleting a gh-pages branch means pages get
      # unpublished
      page.destroy
    end
  end

  def handle_pages_deployments_delete(ref)
    return unless page && ref.to_s.start_with?("refs/heads/")
    # deleting a ref deletes its pages deployment
    page.deployments_for(ref.to_s.sub("refs/heads/", "")).destroy_all
  end

  def check_custom_hooks(old_oid, new_oid, qualified_name, options = {})
    return unless has_pre_receive_hooks?
    if options[:no_custom_hooks].nil? && GitHub.pre_receive_hooks_enabled?
      # Try running pre-receive hooks
      refline = "#{old_oid} #{new_oid} #{qualified_name}"
      begin
        sockstat_data = (options[:reflog_data] || {}).merge(repo_pre_receive_hooks: pre_receive_hooks.to_json).merge(repository.pre_receive_control_vars)
        sockstat_data[:custom_hooks_dir] = GitHub.custom_hooks_dir
        sockstat_data[:rails_env] = Rails.env
        sockstat_data[:is_enterprise] = GitHub.enterprise?
        result = rpc.pre_receive_hook(refline, GitHub::GitSockstat.new(sockstat_data).to_env)
        # XXX tests on linux are sometimes returning 127 (not found?)
        raise Git::Ref::HookFailed, result["out"] + result["err"] if result["status"] != 0 && result["status"] != 127
      rescue GitRPC::SpawnFailure => e

        # if the hooks don't exist, that's then we don't have to run them
        raise unless e.message =~ /Errno::ENOENT/
      end
    end
  end

  # Public: Can the given user commit to the named branch?
  #
  # Returns Boolean
  def can_commit_to_branch?(user, name)
    can_commit_to_branch_status(user, name) != :blocked
  end

  # Public: Can the given user commit to the named branch?
  #
  # Returns (:blocked, :can_bypass, :allowed)
  def can_commit_to_branch_status(user, name)
    status = BranchRuleEvaluator.branch_commitability_status(self, user, name)

    MergeQueue.branch_locked_for_merge_queue?(name, repository: self) ? :blocked : status
  end

  # Public: Protect a branch.
  #
  # name     - String name of the branch to protect
  # creator  - Required User who is establishing branch protection
  # required_status_checks - Optional Hash specifying required status check settings.
  # required_pull_request_reviews - Optional Hash specifying required pull
  #                                   request review  settings.
  # required_signatures - Optional boolean specifying a commit signature requirement.
  # required_linear_history - Optional boolean specifying merge conflict blocking.
  # enforce_merge_queue - Optional boolean specifying whether to enable the merge queue or not.
  # block_force_pushes - Optional boolean specifying force push blocking.
  # block_deletions - Optional boolean modifying branch deletion rules.
  # enforce_admins: - Optional
  # restrictions - Optional Hash specifying restriction settings.
  # required_conversation_resolution - Optional boolean specifying whether all conversations must be resolved or not.
  # lock branch - Optional boolean specifying whether to lock the branch or not
  # lock allows fetch and merge - Optional boolean specifying whether a locked branch allows fetching and merging
  #
  # Returns the ProtectedBranch.
  def protect_branch(name, creator:,
                           required_status_checks: nil,
                           required_pull_request_reviews: nil,
                           required_signatures: nil,
                           required_linear_history: nil,
                           enforce_merge_queue: nil,
                           block_force_pushes: nil,
                           block_deletions: nil,
                           enforce_admins: nil,
                           restrictions: nil,
                           required_conversation_resolution: nil,
                           lock_branch: nil,
                           lock_allows_fetch_and_merge: nil,
                           create_protected: nil,
                           entry_point: nil)
    transaction do
      retries = 0
      begin
        protected_branch = protected_branches.where(name: name).first
        if protected_branch.nil?
          protected_branch_from_rule = heads.find(name)&.protected_branch
          protected_branch = if protected_branch_from_rule
            protected_branch_from_rule.deep_copy_as!(name: name, creator: creator, entry_point: entry_point)
          else
            protected_branches.create!(name: name, creator: creator)
          end
        end
      rescue ActiveRecord::RecordNotUnique
        retries += 1
        if retries >= 3
          raise
        else
          retry
        end
      end

      if required_status_checks
        protected_branch.update_required_status_checks(**required_status_checks)
      else
        protected_branch.clear_required_status_checks
      end

      if required_pull_request_reviews
        protected_branch.enable_required_pull_request_reviews(**required_pull_request_reviews)
      else
        protected_branch.clear_required_pull_request_reviews
      end

      case required_signatures
      when true
        protected_branch.enable_required_signatures
      when false
        protected_branch.clear_required_signatures
      end

      case required_linear_history
      when true
        protected_branch.enable_required_linear_history
      when false
        protected_branch.clear_required_linear_history
      end

      case enforce_merge_queue
      when true
        protected_branch.enable_merge_queue
      when false
        protected_branch.clear_merge_queue
      end

      case block_force_pushes
      when true
        protected_branch.enable_blocked_force_pushes
      when false
        protected_branch.clear_blocked_force_pushes
      end

      case block_deletions
      when true
        protected_branch.enable_blocked_deletions
      when false
        protected_branch.clear_blocked_deletions
      end

      case enforce_admins
      when true
        protected_branch.admin_enforced = true
      when false
        protected_branch.admin_enforced = false
      end

      if restrictions
        restrictions[:entry_point] = entry_point
        protected_branch.update_restrictions(**restrictions)
      else
        protected_branch.clear_restrictions
      end

      case required_conversation_resolution
      when true
        protected_branch.enable_required_review_thread_resolution
      when false
        protected_branch.clear_required_review_thread_resolution
      end

      case lock_branch
      when true
        protected_branch.enable_lock_branch
      when false
        protected_branch.clear_lock_branch
      end

      case lock_allows_fetch_and_merge
      when true
        # allow fetch and merge only applies when branch is locked
        protected_branch.lock_allows_fetch_and_merge = true if protected_branch.lock_branch_enabled?
      when false
        protected_branch.lock_allows_fetch_and_merge = false
      end

      case create_protected
      when true
        protected_branch.enable_create_protected
      when false
        protected_branch.clear_create_protected
      end

      protected_branch.save!
      protected_branch
    end
  end

  # Public: Fetches commits from base_ref. Creates a new ref
  #         in the repository pointing to base_ref.target.
  #
  # base_ref     - The ref to fetch from in the source repository
  # new_ref_name - Optional: The name of the new created branch.
  #                Defaults to the name of base_ref
  # user         - The user to use for the ref update operation
  #
  # Returns the created Ref
  def fetch_commits_from(base_ref, new_ref_name: base_ref.name, user:, reflog_data: {})
    new_ref = heads.find_or_build(new_ref_name)

    rpc.fetch_commits(base_ref.repository.shard_path, base_ref.target_oid)

    new_ref.update(base_ref.target_oid, user, {
      priority: :high,
      post_receive: false,
      clear_ref_cache: true,
      no_custom_hooks: false,
      reflog_data: reflog_data,
    })

    new_ref
  end

  include GitRepository::RefsDependency
end
