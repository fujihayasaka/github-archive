# typed: true
# frozen_string_literal: true

# A good description of what happens from the git-systems perspective can be found here:
# https://github.com/github/github/blob/master/git-bin/git-copy-fork
class ExtractRepositoryOrchestration < RepositoryOrchestration
  step :inspect_environment do
    return :failed, "no existing network" if repository.network.nil?

    return :skipped, "single repo network" if !attach? && include_forks? && repository.network&.repositories&.count == 1
    return :failed, "same network" if new_network_id == repository.network_id
    return :failed, "missing storage" unless repository.exists_on_disk?
    return :failed, "already the root" if !attach? && include_forks? && repository.network_root?
    return :failed, "cannot attach to a network with different visiblity" if attach? && new_network.root.public? != repository.public?
    return :skipped, "an ancestor to this fork is being extracted" if ancestors_being_extracted?
    return :skipped, "a child fork is being extracted" if include_forks? && children_being_extracted?
    return :failed, "not enough disk space available" unless repository.network&.enough_space_to_extract?(repository)
  end

  step :populate_orchestration do
    @old_organization = repository.organization
    @old_network = repository.network
    @old_parent = repository.parent
    data[:was_root] = repository.network_root?
    data[:was_fork] = repository.fork?
    data[:old_network_id] = @old_network&.id
    data[:old_parent_id] = @old_parent&.id
    data[:old_organization_id] = @old_organization&.id # may be nil
    data[:network_size] = T.must(repository.network).repositories.size
    data[:include_forks] = include_forks?
  end

  step :wait_in_queue do
    return if queue_count <= 0

    attempts = 0
    while attempts < 5 do
      attempts += 1

      # Check if we need to wait behind other running orchestrations.
      # Compare how many extracts are running versus how many are allowed to run.
      # We should ignore any in the "waiting" state, since they may have wrongly decided to wait,
      # or more likely the queue_count may have been lowered since they started.
      # Also ignore any orchestrations with an ID greater than ours, since they will wait on us.
      previous_id = T.must(self.id) - 1
      running = self.class.where(id: ..previous_id, state: [:created, :started, :running])
      return if running.size < queue_count

      # We need to wait. Find the end of the queues and put outselves at the end of it.
      # We reuse the existing parent-child relationship in orchestrations to represent the queues.
      # For these purposes, there is no parent or child, so the names are a bit confusing.
      # The child is an orchestration that came before us. It has a parent_id column, and we set that to our ID.
      # The parent is the one that is waiting on the child,
      # When the child finishes, the orchestration framework automatically kicks the parent to run.

      # Deciding which queue to wait on is a bit tricky, since the number of queues may have changed via FF.
      # First, find any orchestrations that have no parent. That means no one is waiting on them.
      # So they are effectively the end of a queue, perhaps of only 1.
      # Next, only consider the last(queue_count) of these, since the number of allowed queues may have gone down.
      end_of_queues = self.class.active.where(id: ..previous_id, parent_id: nil).order(id: :asc).last(queue_count)
      return if end_of_queues.empty?

      # Now that we have the set of queues that we are allowed to join, pick the one with the lowest id.
      # Since our id is by definition larger than every id in the set of queues, whoever comes after us
      # will therefore pick a different queue than the one we queued. Thus we'll evenly populate the queues.
      # This is a good-enough algorithm for orchestrations. It's possible that one queue may have slower
      # orchestrations than others and thus one queue may get longer than another, but it's unlikely and
      # the alternative of counting the length of each queues could be expensive and not worth it (for now).
      child = T.must(end_of_queues.first)

      # To account for race conditions, in the update statement below we require that the child still has nil parent_id
      # before we set that value to ourselves. It's possible another orchestration got in line before us,
      # in which case rows_updated will be 0 and we need to loop back and try again
      rows_updated = self.class.where(id: child.id, parent_id: nil).update_all(parent_id: self.id)

      if rows_updated == 1
        data[:queued_after] = child.id
        log_info("queued after #{child.id}")
        return :waiting
      end

      # log that we hit a race condition, which should be very rare
      log_error("failed to queue extract orchestration")
    end
  end

  job_start

  step :identify_repos do
    @repos_to_extract = include_forks? ? repository.repository_and_descendants : [repository]
    data[:repos_to_extract] = repos_to_extract.map(&:id)
  end

  # if something is wrong with the source file system, fail early.
  # git-janitor will look for common problems and if it cannot fix them, abort.
  step :janitor_fix do
    begin
      repos_to_extract.each do |repo|
        repo.janitor_fix
      end
    rescue GitRPC::CommandFailed, Repository::CommandFailed => e
      return :failed, e.message
    end
  end

  # nwo is part of the checksum, if there is an outdated nwo file on disk
  # then fix it to avoid a checksum mismatch later
  step :ensure_up_to_date_on_disk_nwo do
    repos_to_extract.each do |repo|
      begin
        nwo_content = repo.rpc.fs_read("info/nwo")&.chomp
      rescue GitRPC::SystemError => e
        nwo_content = ""
      end

      # The nwo file is not visible for customers, but knowing the EMU is beneficial when
      # interacting with repositories on the server
      repo.update_nwo_file(repo.name_with_owner) unless repo.name_with_owner == nwo_content # rubocop:disable GitHub/DoNotAllowNameWithOwner
    end
  end

  # If there are unknown/unexpected files that we don't know what to do with, fail early.
  # We'll need to figure out what to do with the unknown file types and
  # update git-copy-fork or git-janitor to handle them.
  # see https://github.com/github/github/blob/master/git-bin/git-copy-fork
  # and https://github.com/github/gitrpcd/blob/main/janitor/policy.go
  step :find_unknown_files do
    repos_to_extract.each do |repo|
      out = repo.rpc.unknown_files
      # we need to fail here and update git-copy-forks to handle the unknown files before allowing this extraction to proceed
      return :failed, "found unknown files: #{out}" if out
    end
  end

  step :garbage_collection do
    begin
      old_network.rpc.nw_gc(geometric: false, auto: true)
    rescue GitRPC::CommandFailed, GitRPC::Protocol::DGit::ResponseError, GitRPC::Timeout => e
      GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:garbage_collection"])
      log_error("nw_gc failed: #{old_network.last_maintenance_at} #{e.message}")
    end
  end

  step :prep_shared_storage do
    # the copy_fork and prepare_copy_fork steps below require the shared storage urls, so make sure they exist
    repos_to_extract.each &:enable_or_disable_shared_storage
  end

  step :create_new_network do
    # new_network may already exist in Attach scenarios, or if this step is re-executed
    return if new_network.present?

    if data[:was_root]
      # the new network gets inserted between any parent network and the old network becomes the child of the new network
      @new_network = old_network.create_parent!(root: repository, parent: old_network.parent)
      # we need to save the old_network's owner_id which just changed.
      old_network.save!
    else
      # the new network is a child of the old network
      @new_network = old_network.children.create(root: repository)
    end

    data[:new_network_id] = @new_network.id
  end

  step :copy_push_rules do
    # ignore validation errors, because our repo is still a fork at this point and cannot have push rules (yet)
    # We need the rules in place now, before it becomes the root to ensure push rules are always in effect
    RepositoryRuleset.copy_rules(old_network.root, repository, ["push"], validate: false)
  end

  step :initialize_replicas do
    # There are some codepaths that depend on this initialization.
    # See repository_removal_test.rb for an example
    if new_network && new_network.needs_dgit_initialization_after_commit?
      new_network.initialize_placeholder_network_replicas
    end
  end

  step :prepare_new_file_system do
    repos_to_extract.each do |repo|
      dup = duplicate_repo_on_different_network(repo, new_network)

      # setup an empty #{repo.network_id}/#{repo.id}.git
      dup.create_git_repository_on_disk(default_branch: repo.default_branch)

      if repo.wiki_exists_on_disk?
        creator =
          GitHub::RepoCreator.new(dup.unsullied_wiki,
            public: dup.public?,
            template: GitHub.repository_template,
            nwo: "#{dup.name_with_owner}.wiki") # rubocop:disable GitHub/DoNotAllowNameWithOwner
        creator.init

        dup_wiki_exists = dup.wiki_exists_on_disk?
        log_info("wiki created: #{dup_wiki_exists}, repo #{dup.dgit_spec}")

        unless dup_wiki_exists
          raise RetryStepError.new("wiki creation failed, repo #{dup.dgit_spec}")
        end
      end

      dup.initialize_git_repository_templates
      dup.enable_shared_storage
    end
  end

  # prepare_copy_fork copies the network files, so is the bulk of the copy.
  # This can be done while the repos are unlocked.
  step :prepare_copy_forks do
    repo_list = repo_and_wiki_ids(repos_to_extract)

    # extend the 30 minute timeout to 1 hour for this step
    # for extremely large repos, 30 minutes is not sufficient.
    # note that jobs regularly get killed about every 1 hour during work hours due to deployments
    new_network.rpc.with_timeout(1.hour) do
      new_network.rpc.prepare_copy_fork(old_network.shared_storage_url, repo_list)
    end
  end

  step :lock_repos do
    repos_to_extract.each do |repo|
      repo.lock_excluding_descendants!(Repository::LockDependency::MOVING)
    end
  end

  step :reparent_forks do
    return if include_forks?
    # If this is a single-repo "detach" scenario, we aren't taking the forks with us, so reparent them to their grandparent
    # Do this before the copy_forks step
    old_network.reparent_forks!(repository)
    old_network.save!
    # If repository was the root, reparent_forks assigned one of its forks to be its parent
    # Reload the repository to pick up the new parent_id so the detach_from_parent step can fix this later
    repository.reload
  end

  step :compute_before_checksum do
    # record the dgit checksum for validation later
    begin
      nw_reader = GitHub::DGit::Routing.preferred_reader_for_network(repository.network_id)
      out = GitHub::DGit::Maintenance.recompute_checksums(repository, nw_reader)
      data[:dgit_checksum_before] = out[:checksum]
    rescue GitHub::DGit::ThreepcFailedToLock => e
      # don't fail if we can't get the checksum
      # retries don't seem to help so just move on
      log_error("Failed to get dgit_checksum_before. #{e.message}")
      GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:compute_before_checksum"])
    end
  end

  step :copy_forks do
    # Re-evaluate what repos need to be extracted each time we run this step.
    # Some may have already been extracted in a previous run and we don't want to re-copy them.
    remaining_repos = remaining_repos_to_extract(repository, [])

    remaining_repos.each do |repo|
      new_network.rpc.copy_fork(old_network.shared_storage_url, "#{repo.id}")
      if repo.wiki_exists_on_disk?
        log_info("copying wiki, repo #{repo.dgit_spec}")
        new_network.rpc.copy_fork(old_network.shared_storage_url, "#{repo.id}.wiki")
      end

      # point the repo at the new network
      repo.set_network(new_network)
      repo.save!
    end
  end

  step :detach_from_parent do
    # This orchestration is for both Extract and Attach, and the new parent is not nil in Attach scenarios
    new_parent_id = attach? ? new_network&.root_id : nil
    repository.update!(parent_id: new_parent_id)
  end

  step :sync_org_owned_private_network_with_forks do
    old_network&.reload&.sync_org_owned_private_network_with_forks
    new_network&.reload&.sync_org_owned_private_network_with_forks
  end

  step :resync_forks do
    repos_to_extract.each do |r|
      r.reload.sync_routes_from_network
    end
    repository.reload
  end

  step :compare_checksums do
    begin
      nw_reader = GitHub::DGit::Routing.preferred_reader_for_network(repository.network_id)
      out = GitHub::DGit::Maintenance.recompute_checksums(repository, nw_reader)
      checksum = out[:checksum]
      data[:dgit_checksum_after] = checksum

      if checksum.nil?
        # we don't need to log a warning here since the exception will be logged as a failed and retried step
        raise RetryStepError.new("dgit checksum is nil")
      end

      if data[:dgit_checksum_before] != data[:dgit_checksum_after]
        # log an error if the checksums don't match, but don't fail
        log_error("dgit checksums do not match")
        GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:compare_checksums.no_match"])
      end
    rescue GitHub::DGit::ThreepcFailedToLock => e
      # don't fail if we can't get the checksum
      # retries don't seem to help here, so just move on
      GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:compare_checksums.failed_to_lock"])
      log_error("Failed to get dgit_checksum_after. #{e.message}")
    end
  end

  step :unlock_repos do
    repos_to_extract.each do |r|
      r.unlock_including_descendants! unless r.locked_on_billing?
    end
  end

  step :delete_source_repos do
    repos_to_extract.each do |repo|
      if repo == repository && data[:dgit_checksum_before] != data[:dgit_checksum_after]
        log_error("keeping extracted root repo in source network to aid checksum mismatch investigation")
        next
      end

      unless repo.exists_on_disk?
        GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:delete_source_repos"])
        log_error("repo #{repo.id} does not exist on new network #{repo.network.id}. Keeping repo in old network #{old_network.id} for investigation")
        next
      end

      # delete the contents from the old network
      dup = duplicate_repo_on_different_network(repo, old_network)
      dup.remove_from_disk

      # delete the wiki from the old network
      if dup.wiki_exists_on_disk?
        # log diagnostic info
        log_info("old wiki: #{dup.dgit_spec}, original_shard_path:#{dup.original_shard_path}, storage_path: #{dup.network.storage_path}, wiki_shard_path: #{dup.wiki_shard_path}")

        # check for residual wiki paths
        if dup.wiki_shard_path == repo.wiki_shard_path ||
          dup.original_shard_path == repo.original_shard_path ||
          dup.network.storage_path == repo.network.storage_path
          GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:delete_source_repos.wiki"])
          log_info("new wiki: #{repo.dgit_spec}, original_shard_path:#{repo.original_shard_path}, storage_path: #{repo.network.storage_path}, wiki_shard_path: #{repo.wiki_shard_path}")
        elsif !GitHub.flipper[:extract_save_wiki].enabled?
          log_info("deleting wiki from repo #{dup.dgit_spec}")
          dup.remove_wiki_from_disk
        end
      end
      dup.rpc.remove # avoid flaky tests
    end
  end

  step :update_organization do
    repos_to_extract.each do |r|
      r.update_organization
    end
    new_network.update_permissions_on(repos_to_extract, old_organization)
  end

  step :async_copy_media do
    Media::Transition.async_copy(old_network, new_network)
  end

  step :enable_shared_storage do
    repos_to_extract.each &:enable_or_disable_shared_storage
  end

  step :reload_private_repos do
    T.must(repository.owner).owned_private_repositories.reload
  end

  step :dgit_reload_routes do
    repository.dgit_reload_routes!
  end

  step :touch_repo do
    repository.touch
  end

  step :audit_logs do
    action = include_forks? ? "extract" : "detach"
    name = Audit.context[:from]&.start_with?("stafftools") ? "staff.repo_#{action}" : "repo.#{action}"
    GitHub.instrument name, repo: repository, old_network_id: old_network&.id
  end

  step :destroy_old_network do
    if attach?
      old_network.reparent_child_networks(new_network_id)
      if old_network.active_and_deleted_repositories.count == 0
        old_network.destroy
        @old_network = nil
      end
    end
  end

  # this is a best-effort attempt to replace the old network
  # don't retry and don't fail if it fails
  step :garbage_collection_after_copy do
    begin
      old_network.rpc.nw_gc(geometric: false, auto: true) if old_network.present?
    rescue GitRPC::CommandFailed, GitRPC::Protocol::DGit::ResponseError, GitRPC::Timeout => e
      GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:garbage_collection_after_copy"])
      log_error("nw_gc failed: #{e.message}")
    end
  end

  # this is a best-effort attempt to repack the new network
  # don't retry and don't fail if it fails
  step :garbage_collection_new_network do
    begin
      new_network.rpc.nw_gc(geometric: false, auto: true)
    rescue GitRPC::CommandFailed, GitRPC::Protocol::DGit::ResponseError, GitRPC::Timeout => e
      GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:garbage_collection_new_network"])
      log_error("nw_gc failed: #{e.message}")
    end
  end

  step :calculate_network_counts do
    old_parent.reload.calculate_network_counts! if old_parent
    repository.reload.calculate_network_counts! if attach? || !include_forks?
  end

  step :reindex_network do
    if attach? || !include_forks? || data[:reindex]
      repository.reindex_after_network_operation(data[:was_root], data[:was_fork], old_network)
    end
  end

  step :publish_extracted do
    message = build_hydro_event_message.merge({
      was_root: data[:was_root],
      was_fork: data[:was_fork],
      old_network_id: data[:old_network_id],
      old_parent_id: data[:old_parent_id],
    })
    if include_forks?
      message = message.merge({
        old_organization_id: data[:old_organization_id],
        network_size: data[:network_size],
      })
      publish_hydro_event(schema: "github.repositories.v1.Extracted", message:)
    else
      publish_hydro_event(schema: "github.repositories.v1.Detached", message:)
    end
  end

  ###############################################################################################

  sig { returns(Repository) }
  def repository
    T.must(super)
  end

  def target_urls
    return @target_urls if defined?(@target_urls)
    delegate = GitHub::DGit::Delegate::Network.new(new_network.id, new_network.storage_path)
    @target_urls = delegate.get_write_routes.map { |route| route.rsync_url }
  end

  def repo_and_wiki_ids(repositories)
    repositories.map do |repo|
      if repo.wiki_exists_on_disk?
        [repo.id.to_s, "#{repo.id}.wiki"]
      else
        repo.id.to_s
      end
    end.flatten
  end

  # Similar to repo.repository_and_descendants, but excludes the forks that have already moved to the new network
  def remaining_repos_to_extract(repo, repositories)
    repositories << repo
    repo.children.where(source_id: old_network.id).each do |fork|
      remaining_repos_to_extract(fork, repositories)
    end
    repositories
  end

  # Create a dummy repo object on the new network, to be used for copying the repo contents
  def duplicate_repo_on_different_network(repo, network)
    dup = repo.dup

    dup.id = repo.id
    dup.raw_data = ""
    dup.network = network
    dup.reset_git_cache

    if GitHub.flipper[:extract_wiki_fix].enabled? && repo.unsullied_wiki.exist?
      dup.unsullied_wiki(true)
      dup.unsullied_wiki.reset_git_cache
    end

    # it is critical to reload the routes here so we don't manipulate the wrong network!
    dup.dgit_reload_routes!
    dup.set_rpc_network_override(network)

    if repo.unsullied_wiki.exist?
      unless GitHub.flipper[:extract_wiki_fix].enabled?
        dup.unsullied_wiki(true)
      end
      dup.unsullied_wiki.set_rpc_network_override(network)
    else
      dup.has_wiki = false
    end
    dup.freeze
    dup
  end

  def new_network_id
    data[:new_network_id]
  end

  def new_network
    @new_network ||= RepositoryNetwork.find_by(id: new_network_id) if new_network_id
  end

  def old_network
    @old_network ||= RepositoryNetwork.find_by(id: data[:old_network_id])
  end

  def old_parent
    @old_parent ||= Repository.find_by(id: data[:old_parent_id])
  end

  def repos_to_extract
    @repos_to_extract ||= Repository.where(id: data[:repos_to_extract]).order(:id).to_a
  end

  def old_organization
    @old_organization ||= Organization.find_by(id: data[:old_organization_id])
  end

  def attach?
    data[:attach].present?
  end

  def include_forks?
    !!data[:include_forks]
  end

  def wait_in_queue?
    data[:wait_in_queue].present?
  end

  def queue_count
    return data[:queue_count] if data[:queue_count].present?

    count = GitHub.flipper[:extract_queue_count].percentage_of_time_value.to_i
    data[:queue_count] = count
  end

  def stop_after_waiting?(_unsuccessful_children)
    # This method is only called by the base class if we blocked ourselves in the beginning due to queue_count.
    # If our "child" orchestration fails, we don't care, we are running anyway.
    # That "child" was just the orchestration in front of us in the queue
    false
  end

  on_end_orchestration do |_error_message, _error_klass|
    # reload our orchestration to get the latest parent_id
    # because another orchestration may have queued behind us since we last loaded ourself
    self.reload
  end

  def ancestors_being_extracted?
    # check if any of our parent forks are being extracted
    ids = []
    repo = repository
    while (parent = repo.parent).present?
      break if ids.include?(parent.id) # avoid infinite loops due to misconfigured forks
      ids << parent.id
      repo = T.cast(parent, Repository) # rubocop:todo GitHub/AvoidCast
    end

    # now check if any of those parents are being extracted
    self.class.active.where(repository_id: ids).any?
  end

  def children_being_extracted?
    ids = repository.descendant_ids
    self.class.active.where(repository_id: ids).any?
  end
end
