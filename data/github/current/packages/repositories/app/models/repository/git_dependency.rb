# typed: true
# frozen_string_literal: true

# used to store methods that relate to a repository interacting with the underlying
# Git repository via gitrpc

module Repository::GitDependency
  extend T::Helpers

  requires_ancestor { Repository }

  DU_IGNORE = ["refs/__gh__/*", "refs/pull/*"]
  JUNK_DIRS = ["dot_git", ".git", ".hg", ".svn", ".sass-cache", "build", "log", "tmp", "vendor"]

  # Compare base and head refs with a new GitHub::Comparison object.
  #
  # base  - The extended ref identifying the commit to act as the
  #         base of the comparison.
  # head  - The extended ref identifying the commit to act as the
  #         head of the comparison.
  # limit - Numeric limit for the total number of commits to retrieve.
  def comparison(base, head, limit = 1000, pull = nil)
    GitHub::Comparison.deprecated_build(self, base, head, limit: limit, pull: pull)
  end

  ##
  # Git Repository Access

  # Get the host on which the repo (network) is stored.
  # For DGit, get the best available host on which the repo is stored.
  # For unrouted repos (nil network or no healthy DGit replicas), throws
  # an exception.
  def host
    dgit_read_routes.first.host
  end
  alias route host

  # dgit_spec is the canonical description for a repository entity within
  # dgit/spokes. It avoids using any PII and encodes network membership.
  def dgit_spec(wiki: false)
    if wiki || dgit_repo_type == GitHub::DGit::RepoType::WIKI
      "#{network_id}/#{id}.wiki"
    else
      "#{network_id}/#{id}"
    end
  end

  def namespace
    dgit_repo_type == GitHub::DGit::RepoType::WIKI ? "wiki" : "repository"
  end

  def dgit_delegate_for_update_refs_coordinator
    if dgit_repo_type == GitHub::DGit::RepoType::WIKI
      GitHub::DGit::Delegate::Wiki.new(network_id, id, original_shard_path, spokes_api_context)
    else
      GitHub::DGit::Delegate::Repository.new(network_id, id, original_shard_path, spokes_api_context)
    end
  end

  def dgit_delegate
    @dgit_delegate ||= GitHub::DGit::Delegate::Repository.new(network_id, id, no_dgit_shard_path, spokes_api_context)
  end

  def dgit_wiki_delegate
    @dgit_wiki_delegate ||= GitHub::DGit::Delegate::Wiki.new(network_id, id, wiki_shard_path, spokes_api_context)
  end

  def coalesce_dgit_updates?
    false
  end

  def repository_spec
    "#{network_id}/#{id}"
  end

  # Get the host on which the repo (network) is stored.
  # For DGit, get the best available host on which the repo is stored.
  # If the repo is unrouted in DGit, eat the error.  "unrouted" isn't a
  # real host, but if the text is going to be forwarded opaquely to a log
  # or a web pages (e.g. stafftools), this is better than an exception.
  def safe_route
    return "unrouted" if network.nil?
    route
  rescue GitHub::DGit::UnroutedError
    "unrouted"
  end

  # The absolute path on disk to the repository.
  def shard_path
    mapped_shard_path(map_dgit_dev: true)
  end

  def no_dgit_shard_path
    mapped_shard_path(map_dgit_dev: false)
  end

  def mapped_shard_path(map_dgit_dev:)
    if name&.end_with?(".wiki") && base_repo = Repository.nwo(name_with_owner.chomp(".wiki"))
      if map_dgit_dev
        base_repo.unsullied_wiki.shard_path
      else
        base_repo.unsullied_wiki.original_shard_path
      end
    else
      fail "no shard_path for repo without a network" unless network_id
      fail "no shard_path for repo without an id" unless id

      # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      if map_dgit_dev && (Rails.env.development? || Rails.env.test?)
        # map route to a dgit subdirectory in dev and test
        dgit_read_routes.first.path
      else
        original_shard_path
      end
    end
  end

  # Path to where the repository's git data is stored on disk.
  #
  # Returns a path string, ex. "/data/repositories/1/nw/1d/cc/57/117302/1.git",
  # or raises GitHub::DGit::UnroutedError if repo network does not exist
  def original_shard_path
    raise GitHub::DGit::UnroutedError if network_id.nil? || network.nil?
    "#{T.must(network).storage_path}/#{id}.git"
  end

  def running_on_cache_server?
    !!ENV["ENTERPRISE_CLUSTER_CACHE_LOCATION"]
  end

  # Get all routes that can be used for read-only operations, in order of preference.
  def dgit_read_routes(cache_servers_ok: false)
    if !@dgit_read_routes
      @dgit_read_routes = dgit_delegate.get_read_routes
    end

    read_routes = if cache_servers_ok && running_on_cache_server?
      @dgit_read_routes.select(&:cache_server?)
    else
      @dgit_read_routes.reject(&:cache_server?)
    end
    read_routes
  end

  def dgit_wiki_read_routes(cache_servers_ok: false)
    if !@dgit_wiki_read_routes
      @dgit_wiki_read_routes = dgit_wiki_delegate.get_read_routes
    end

    read_routes = if cache_servers_ok && running_on_cache_server?
      @dgit_wiki_read_routes.select(&:cache_server?)
    else
      @dgit_wiki_read_routes.reject(&:cache_server?)
    end
    read_routes
  end

  # Get all routes that can be used for read-write operations, in order of preference.
  def dgit_write_routes
    return @dgit_write_routes if @dgit_write_routes

    @dgit_write_routes = dgit_delegate.get_write_routes
  end

  # Get all routes that can be used for 3PC operations, in order of preference.
  def dgit_3pc_routes
    return @dgit_3pc_routes if @dgit_3pc_routes

    @dgit_3pc_routes = dgit_delegate.get_3pc_routes
  end

  def dgit_wiki_write_routes
    return @dgit_wiki_write_routes if @dgit_wiki_write_routes

    @dgit_wiki_write_routes = dgit_wiki_delegate.get_write_routes
  end

  # Get all routes, even unhealthy ones, in an undefined order.
  # Do not use this unless you are writing debugging, logging, or maintenance code.
  def dgit_all_routes
    return @dgit_all_routes if @dgit_all_routes

    delegate = GitHub::DGit::Delegate::Network.new(network_id, original_shard_path)
    @dgit_all_routes = delegate.get_all_routes
  end

  # Clear all remembered DGit routes.
  def dgit_reload_routes!
    @dgit_read_routes = @dgit_write_routes = @dgit_3pc_routes = @dgit_all_routes = nil
    @dgit_wiki_read_routes = @dgit_wiki_write_routes = nil
    @dgit_delegate = @dgit_wiki_delegate = nil
    @rpc = nil
    @spokes_api = nil
    @spokes_api_context = nil
  end

  def recompute_checksums(voting_strategy, read_host, ignore_dissent: false) # XXX: FIXME: Move this logic to callers and out of this AR class.
    tpc = GitHub::DGit.update_refs_coordinator(self)
    tpc.recompute_checksums(voting_strategy, read_host, ignore_dissent: ignore_dissent)
  end

  # The maintenance queue used to enqueue jobs that run on the fs machine.
  #
  # Returns the maintenance queue name.
  def maintenance_queue_name
    network&.maintenance_queue_name
  end

  # Updates the nwo (name with owner) to a file in the git repo.
  # This method should be used as the single entry point for creating/updating
  # the nwo file.
  #
  # We go through spokes 3PC by default unless spokesd is not enabled in the monolith.
  # If spokesd is not enabled we will instead go through legacy 3PC. The outcome of
  # this is that production will always use spokes 3PC while our tests will continue
  # using legacy 3PC. This compromise was made because of the significant effort
  # required to fix all existing tests to use spokesd. Eventually when all 3PC legacy
  # code is removed from the monolith this function should always go through spokes
  # 3PC regardless of the environment.
  def update_nwo_file(nwo)
    return unless repository.exists_on_disk?

    use_spokesd = GitHub.spokesd_enabled?
    if use_spokesd
      delegate = repository.dgit_delegate_for_update_refs_coordinator
      tpc = GitHub::DGit::SpokesdThreePhaseCommitClient.new(repository.full_name, delegate)
      tpc.update_nwo_file(nwo)
    else

      # Update through gitrpc (the current way)
      GitHub::DGit.with_dgit_lock(repository) do
        repository.rpc.fs_write("info/nwo", nwo)
      end
    end
  end

  # Write the name to a file in the git repo.
  # This is done without the distributed dgit lock, so is racy
  # See GitHub::Spokes.client.write_nwo_file for a safer approach
  def write_nwo_file_unsafe(nwo = name_with_owner)
    return unless exists_on_disk?
    rpc.fs_write("info/nwo", nwo)
    GitHub::DGit::Maintenance.safely_recompute_checksums(self, :vote)
  rescue Object => e # rubocop:todo Lint/RescueException
    Failbot.report(e)
  end

  # Is the repository server online and serving requests?
  def online?
    rescue_offline { rpc.online? }
  end

  # Try a block, and rescue all the errors that #online? rescues.
  def rescue_offline(result_if_offline: false)
    yield
  rescue GitRPC::InvalidRepository, GitRPC::RepositoryOffline, GitRPC::ConnectionError, Repository::RpcDependency::UnroutedError, GitHub::DGit::UnroutedError, GitRPC::Timeout, GitHub::Spokes::ClientError => e
    # If the repo is unrouted, we don't want to proceed with
    # git access (which blows up). But we also want to record
    # the problem repo to a special bucket.
    Failbot.report(e, app: "github-unrouted", "gh.repo.id": id)
    result_if_offline
  end

  # Are there routes for this repository?
  #
  # This is quicker than checking #online? and is a reasonably
  # close approximation to checking if GitRPC calls will succeed.
  def routed?
    host.present?
  rescue GitHub::DGit::UnroutedError => e
    Failbot.report(e, app: "github-unrouted", "gh.repo.id": id)
    false
  end

  # Resets the git cache key so that it's up to date with the repositories
  # pushed_at timestamp. This is typically only used in tests when a ref is
  # updated and you need to retrieve the updated ref values.
  def reset_git_cache
    @rpc = nil
    remove_instance_variable :@empty if defined?(@empty)
    reset_refs
  end

  # Get list of all files in tree.
  #
  # Designed for finder search results, so it excludes certain junk files by default.
  #
  # tree_oid - the oid of the tree to list
  # skip_directories - an array of which directories to ignore, as strings
  # list_directories - a boolean to list directories as well as files
  # return_separate_lists - a boolean to return a hash with separate lists for files and directories
  #
  # Returns Array of String file paths.
  def tree_file_list(tree_oid, skip_directories: JUNK_DIRS, list_directories: false, return_separate_lists: false)
    rpc.tree_file_list(tree_oid,
      list_directories: list_directories,
      list_submodules: false,
      skip_directories: skip_directories,
      override_skipdirs_using_gitattributes: true,
      return_separate_lists: return_separate_lists
    )
  end

  # Public: check if a file exists in the repository
  #
  # path - String full path
  # ref  - String ref to check for path
  #        (optional, defaults to default branch)
  #
  # Note this uses a very UNIX-y definition of "file" that's more like "directory entry"
  #
  # Returns Boolean
  def includes_file?(path, committish = default_branch)
    return true if path.empty? # repos always have a folder at their root
    return false unless ref = refs[committish]
    includes_file_at_commit?(path, ref.target_oid)
  end

  # Public: check if a file exists in the repository at a commit
  #
  # path - String full path
  # commit_oid - The commit oid to check at
  #
  # Note this uses a very UNIX-y definition of "file" that's more like "directory entry"
  #
  # Returns Boolean
  def includes_file_at_commit?(path, commit_oid)
    return true if path.empty? # repos always have a folder at their root
    includes_file_spokes?(path, commit_oid)
  end

  # Public: check if a directory exists in the repository
  #
  # path - String full path
  # ref  - String ref to check for path
  #        (optional, defaults to default branch)
  #
  # Unlike #includes_file?, this checks if the path actually points to a directory (tree)
  #
  # Returns Boolean
  def includes_directory?(path, committish = default_branch)
    return true if path.empty? # repos always have a folder at their root
    return false unless ref = refs[committish]
    includes_file_spokes?(path, ref.target_oid, type: :TYPE_TREE)
  end

  private def includes_file_spokes?(path, commit_oid, type: nil)
    selector = {
      by_treeish_and_path: {
        treeish: { oid: { id: commit_oid } },
        path: { name: SpokesAPI::Util.normalize_path(path) }
      }
    }
    selector[:object_type] = { type: } unless type.nil?

    !spokes_api.resolve_objects_by([selector]).items.first.object.nil?
  rescue SpokesAPI::NotFound, SpokesAPI::InvalidArgument
    false
  end

  # Determines if the repository contains Xcode project files, allowing it
  # to be opened directly within Xcode after cloning.
  #
  # Returns true for Xcode repositories.
  def xcode_project?
    return false unless ref = refs[default_branch]
    spokes_api.list_tree_entries(tree_oid: ref.target_oid).entries.any? do |entry|
      entry.path.name.end_with?(".xcodeproj", ".xcworkspace", ".playground")
    end
  rescue SpokesAPI::NotFound, SpokesAPI::InvalidArgument
    false
  end

  # Public: find the longest existing part of a given path
  #
  # path - String full path
  # ref  - String ref to check for path
  #        (optional, defaults to default branch)
  #
  # Returns String path
  def longest_existing_subpath(path, ref = default_branch)
    return "" unless path
    redirect_path = path
    unless redirect_path.nil?
      until includes_directory?(redirect_path, ref)
        redirect_path = redirect_path.split("/")[0...-1].join("/")
      end
    end
    redirect_path = "" if redirect_path == "/"
    redirect_path
  end

  # Public: check if a path is okay for a file (editing or creating)
  #
  # path - String full path
  # ref  - String ref to check for path
  #        (optional, defaults to default branch)
  #
  # Returns Boolean
  def valid_file_path?(path, ref = default_branch)
    dir_segments = File.dirname(path).split("/")
    dir_segments = [] if dir_segments == ["."]

    file_indexes = dir_segments.each_index.select do |i|
      check_path = dir_segments[0..i]&.join("/")
      file = includes_file?(check_path, ref)
      dir  = includes_directory?(check_path, ref)

      if file && !dir
        # definitely not valid if something somewhere in the dirname is a regular file
        return false
      end
    end

    file = includes_file?(path, ref)
    dir  = includes_directory?(path, ref)

    !(file && dir)
  end

  # Check if the repository directly exists on disk on the storage server. This
  # always makes an RPC call and should be used sparingly. Just because a
  # repository exists does not necessarily mean it has any branches, tags, or
  # other objects. The #empty? method is often a much better check for whether a
  # repository is in a useful state.
  #
  # If the repository isn't routed, returns false since there's no repo to check.
  #
  # Returns true when the repository exists.
  def exists_on_disk?
    host && shard_path && rescue_offline { rpc.exist? }
  rescue GitHub::DGit::UnroutedError
    false
  end

  # Check if the repository is "empty" via Spokes. This logic basically matches #empty? which uses GitRPC instead.
  #
  # Returns true when the repository is empty, false otherwise.
  def empty_with_spokes?
    return @empty_with_spokes if defined?(@empty_with_spokes)
    @empty_with_spokes =
      begin
        if (pushed_at.blank? && !fork?) || owner.nil?
          true
        else
          !spokes_api.references_exist.any
        end
      rescue Errno::ENOENT, SpokesAPI::NotFound
        # If the repo doesn't exist on disk yet then yes, it's definitely
        # empty.
        true
      end
  end

  # Check if the repository is "empty". Empty repositories exist on disk but do
  # not have any branches, tags, or other refs and therefore no commits.
  #
  # NOTE Because this method is very frequently used in before filters and other
  # early-on code in controller actions, it has been highly optimized to avoid an
  # RPC call to the storage servers to determine emptyness. Do not change this
  # unless you know what you're doing / know how to measure these types of perf
  # changes.
  #
  # Returns true when the repository is empty, false otherwise.
  def empty?
    return @empty if defined?(@empty)
    @empty =
      begin
        if (pushed_at.blank? && !fork?) || owner.nil?
          true
        else
          # Assume the repo is not empty if we hit spokes errors.
          # We will show a custom 500 page.
          with_database_error_fallback(fallback: false) do
            refs.empty?
          end
        end
      rescue GitRPC::Timeout
        false
      end
  end

  def async_empty?
    Promise.all([async_internal_repository, async_owner, async_network]).then do
      empty?
    end
  end

  # This method matches the results of empty? within around 99.994% accuracy and is much faster.
  # It can be used in places where sureity of emptiness is not absolutely required.
  # Important note the mismatches between this method and empty? occur when empty? returns true.
  def probably_empty?
    return @probably_empty if defined?(@probably_empty)
    return @probably_empty = false if repository.fork?
    @probably_empty = repository.never_pushed_to? ? repository.empty? : false
  end

  # Is this repository being created?  For repositories in dgit, we examine
  # the voting replicas to see if all were created recently _and_ any
  # are current in the `creating` state.
  def creating?
    return @creating if defined?(@creating)
    @creating =
      begin
        voting_replicas = GitHub::DGit::Routing.all_repo_replicas(self.id).select(&:voting?).sort_by(&:created_at)
        ready = voting_replicas.select { |r| r.checksum != "creating" }

        if ready.length >= GitHub.dgit_quorum(dgit_copies)
          false
        else
          if voting_replicas.empty?
            raise GitHub::DGit::NoVotingReplicas, "id:#{id}, network:#{source_id}"
          end
          # If the oldest replica is newer than 5 minutes old, then this is
          # a new repository being created.
          (Time.now - voting_replicas.first.created_at) < 5.minutes
        end
      end
  end

  def ready_for_writes?
    dgit_write_routes.any? && !creating?
  rescue GitHub::DGit::UnroutedError, GitHub::DGit::InsufficientQuorumError
    false
  end

  def availability
    @availability ||= Repository::Availability.new(self)
  end

  def availability_status
    availability.state
  end

  # Determine if this repository is offline. This accounts for the storage
  # server being down and also for cases where the storage server is up but the
  # repository is not available on disk due to the partition not being mounted
  # or a move being in progress.
  #
  # Returns true if the repository's storage server is offline or if the
  # repository doesn't exist on disk more than five minutes after being created.
  def offline?
    with_database_error_fallback(fallback: true) do
      !online? ||
        (T.must(created_at) < 5.minutes.ago && !exists_on_disk?)
    end
  end

  # Ensures the repository exists on disk. This forks the parent repository when
  # the parent_id is set or creates a new bare repository when there is no
  # parent repository.
  def setup_git_repository
    return if exists_on_disk?

    if advisory_workspace?
      RepositoryCloneJob.perform_later(parent_advisory_repository, self)
    else
      setup_new_git_repository
    end
    reset_memoized_attributes
  end

  def setup_new_git_repository(skip_init: false)
    create_git_repository_on_disk
    return if skip_init
    initialize_git_repository_templates
    now = Time.now
    update_pushed_at now
    async_backup(opts: { pushed_at: now })
  end

  def create_repository_in_spokes(source_repository: nil, skip_source_repo_on_clone: true)
    if fork?
      #TODO: (tech debt)
      # It is necessary for tests.
      # The repositories created with factory_bot
      # rely on this to make the repository routed by spokes.
      self.initialize_replicas_from_network rescue false
    elsif advisory_workspace?
      spokes_api_facade.clone_repository(source_repository: parent_advisory_repository)
    elsif source_repository
      spokes_api_facade.clone_repository(source_repository: skip_source_repo_on_clone ? nil : source_repository)
    else
      spokes_api_facade.create_repository
    end
  end

  # Synchronize objects from this repository into the shared network.git
  # repository, or update an isolated repository's incremental commit-graphs.
  # This must eventually be called any time a repository's ref space is
  # modified.
  #
  # This is a potentially long-running operation. Use the
  # synchronize_shared_storage method to queue up a job instead.
  #
  # Returns nothing.
  def synchronize_shared_storage!
    rpc.nw_sync(ignore_locking_errors: true)
  end

  # Enqueue a background job to run synchronize_shared_storage!.
  def synchronize_shared_storage
    queue = maintenance_queue_name
    if queue.ok?
      RepositorySyncJob.set(queue: queue.value!).perform_later(id)
      true
    else
      nil
    end
  end

  # Returns the maximum size of a cruft pack generated when repacking this
  # repository.
  #
  # Returns: Integer.
  def max_cruft_size
    if feature_flag_enabled_or_raise?(:gitrpc_max_cruft_size_3g) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      3.gigabytes
    elsif feature_flag_enabled_or_raise?(:gitrpc_max_cruft_size_2g) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      2.gigabytes
    elsif feature_flag_enabled_or_raise?(:gitrpc_max_cruft_size_1g) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      1.gigabyte
    else
      nil
    end
  end

  # Run `git nw-repack` in safe mode. This a faster, less agressive version
  # of git-gc used for repository maintenance. Safe mode (-k) implies that
  # no objects will get purged from the repository, even if they are not
  # reachable
  #
  # geometric: whether to run a geometric repack.
  #
  # Returns nothing.
  def repack(geometric: false)
    GitRPC::Util.with_repack_error_handler do
      # Timeouts are handled on a per rpc client level, explicitly run `nw_repack` with a 3 hour upper boundary.
      # See also `GitHub::Jobs::NetworkMaintenance` as the most likely calling party
      rpc.with_timeout(3.hours) do
        rpc.nw_repack(geometric: geometric, max_cruft_size: max_cruft_size)
      end
    end
    nil
  end

  # Run git nw-fsck on the repository
  def nw_fsck(trust_synced: false)
    rpc.nw_fsck(trust_synced: trust_synced)
  end

  # Run git restore-objects on the repository, to try and repair it.
  def restore_objects(options = {})
    rpc.restore_objects(options)
  end

  # Retrieve last run git-fsck output for the repository. This will never cause
  # an actual fsck operation.
  def fsck
    res = rpc.last_fsck(never: true)
    res["out"]
  end

  # Run git-fsck on the repository and store the result at <GIT_DIR>/fsck.
  def fsck!
    res = rpc.last_fsck(force: true)
    res["out"]
  end

  # Queue a job to run git-fsck on the repository.
  def async_fsck
    RepositoryFsckJob.perform_later(id)
  end

  # Update the disk_usage attribute in the database
  # Returns the newly recorded disk usage value in kilobytes.
  def update_disk_usage
    ActiveRecord::Base.connected_to(role: :writing) do
      ignored_refs = DU_IGNORE
      ignored_refs += ["#{MergeQueue::READ_ONLY_REF_PREFIX}*"] if merge_queue_enabled?
      disk_usage = exists_on_disk? && rpc.repo_disk_usage(ignored_refs)
      disk_usage = (disk_usage || 0) / 1024
      update_column :disk_usage, disk_usage
      disk_usage
    end
  end

  # Get a human-friendly representation of the repository disk usage.
  #
  # Returns a String
  def human_disk_usage
    # number_to_human_size expects bytes, but disk_usage is reported in
    # kilobytes, so convert it first.
    number_to_human_size(disk_usage * 1024)
  end

  # How many copies (replicas) of each repo network to aim for.
  #
  # Returns a small, odd integer.
  def dgit_copies
    @dgit_copies ||= if GitHub::DGit::ColdStorage.is_network_read_heavy?(network_id)
      GitHub.dgit_read_heavy_copies
    else
      GitHub.dgit_default_copies
    end
  end

  # TODO: move this method out of repository once we have repo specs of some sort
  # public: true if the repo is currently being repaired
  def repairing?
    if feature_flag_enabled_or_raise?(:spokes_block_cprmc_with_multiple_bad_replicas) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      return dgit_read_routes.size < (dgit_copies - 1)
    end

    false
  end

  # Public: Determine the "best" merge base between two commits.
  #
  # Returns a String containing the best merge commit oid, or nil.
  def best_merge_base(base_sha, head_sha, timeout: nil)
    rpc.best_merge_base(base_sha, head_sha, timeout: timeout)
  end

  # Public: Determines if a commit with the given object ID is reachable in
  # this repository (i.e. in a branch or tag, not a fork).
  #
  # This has some statting and logging that's a bit ugly due to the need to
  # carefully instrument this.
  #
  # Returns: Boolean
  def is_commit_in_branch_or_tag?(oid)
    timed_out = false
    found = false

    begin
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      commit = commits.find(oid, check_reachability: true)
      found = !!commit
    rescue GitRPC::ObjectMissing
      found = false
    rescue GitRPC::Timeout
      timed_out = true
      found = false
    ensure
      finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      elapsed_ms = ((finish - T.must(start)) * 1000).round
      GitHub.dogstats.timing "repository.commit_is_in_branch_or_tag", elapsed_ms, tags: ["found:#{found}", "timed_out:#{timed_out}"]

      GitHub.logger.info(
        "Completed finding object ID in repo",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "git.commit.oid" => oid,
        "gh.repo.find_commit.timed_out" => timed_out,
        "gh.repo.find_commit.found" => found,
        "gh.repo.name_with_owner" => name_with_owner,
        "gh.repo.find_commit.elapsed_ms" => elapsed_ms
      )
    end
  end

  # This column represents the last time a ref was added or deleted to this
  # repo.  It's populated on push but is also being lazily backfilled, so if it
  # happens to be read during a request when it's still NULL we will do the
  # work to query the Pushes log to populate it.  This work will only ever be
  # done at most once for any repo.
  def refset_updated_at
    super || backfill_refset_updated_at
  end

  private def backfill_refset_updated_at
    start = GitHub::Dogstats.monotonic_time
    last_refset_change = ActiveRecord::Base.connected_to(role: :reading) do
      # On failure or absence, the current time works fine as a default
      begin
        Repositories.domain.pushes.refset_updated_at(repository_id: T.must(self.id), limit_execution_ms: 2000) || Time.current

      rescue ActiveRecord::StatementTimeout
        Time.current
      end
    end
    # instead of setting the attr on this instance and saving it, flush to the
    # database and just update the in-memory attr.  We don't want to
    # inadvertently save a dirty attribute that wasn't ready!
    ActiveRecord::Base.connected_to(role: :writing) do
      Repository.where(id: id).update_all(refset_updated_at: last_refset_change)
    end
    !self.destroyed? && self.refset_updated_at = last_refset_change
    last_refset_change
  ensure
    GitHub.dogstats.distribution("repository.backfill_refset_updated_at", GitHub::Dogstats.duration(start))
  end

  # Public: Is the given branch name or commit SHA one that exists in this repository?
  #
  # maybe_branch - String branch name or commit SHA or ref
  #
  # Returns a Boolean.
  def valid_branch?(maybe_branch)
    extractor = GitHub::RefShaPathExtractor.new(self)
    branch, _ = extractor.call(maybe_branch)
    !branch.nil?
  end

  # Public: Has the network of this repository got any LFS objects?
  # Most repositories allow LFS content, but many of them never used it.
  # This method checks whether any actual LFS content has ever been pushed to this network.
  # It may return false positives if LFS files are only reachable from another fork.
  # It's not possible to push LFS objects to a fork without write access to the main repository,
  # because of billing, so we're good with this cheaper check at the network level.
  #
  # Returns a Boolean.
  def has_lfs_files?
    return @has_lfs_files if defined?(@has_lfs_files)
    @has_lfs_files = Media::Blob.where(repository_network_id: network_id).exists?
  end

  # Fetches commits from another repo in the same network
  # This method performs checking to ensure that the repo is in the same network
  # or is an advisory workspace.
  #
  # Returns true if successful, false otherwise
  def fetch_commits_from_network(other_repo, commit_oid)
    if network_id == other_repo.network_id || advisory_workspace?
      rpc.fetch_commits(other_repo.shard_path, commit_oid)
      true
    else
      false
    end
  end
end
