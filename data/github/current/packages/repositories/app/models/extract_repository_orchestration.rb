# typed: true
# frozen_string_literal: true

# A good description of what happens from the git-systems perspective can be found here:
# https://github.com/github/github/blob/master/git-bin/git-copy-fork
class ExtractRepositoryOrchestration < RepositoryOrchestration
  validate :validate_orchestration, on: :create

  # validate that the request makes sense before creating the orchestration record
  def validate_orchestration
    if attach?
      errors.add(:base, :extract, message: "cannot attach to same network") if new_network_id == repository.network_id
      errors.add(:base, :extract, message: "destination network does not exist") if new_network.nil?
      errors.add(:base, :extract, message: "destination network has no root") if new_network.root.nil?
      errors.add(:base, :extract, message: "destination network has different visibility") if new_network.root&.public? != repository.public?
    elsif include_forks?
      errors.add(:base, :extract, message: "already alone in the network") if repository.network&.repositories&.count == 1
      errors.add(:base, :extract, message: "already the root of the network") if repository.network_root?
    end
    # note that for detach we allow the above scenarios. This is for stafftools if we want to remove a fork from a a network with a deleted fork
  end

  # inspect the environment for issues we know will cause failures and abort early
  step :inspect_environment do
    # Return :skipped if the orchestration is invalid due to something in the environment,
    # but we haven't made any changes so it's OK to ignore this orchestration.
    # There's no real need to retry a :skipped orchestration; they can just start a new orchestration if they want.
    # However we may retry this orchestration if it was initiated by a visibility orchestration and that gets retried.
    # We don't use :failed here because that means we started making changes, something went wrong that needs investigation,
    # and retrying where it left off might be a good idea. That will apply if we get past this step.
    return :skipped, "no existing network" if repository.network.nil?
    return :skipped, "missing storage" unless repository.exists_on_disk?
    return :skipped, "not enough disk space available" unless repository.network&.enough_space_to_extract?(repository)
    return :skipped, "an ancestor to this fork is being extracted" if ancestors_being_extracted?
    return :skipped, "a child fork is being extracted" if include_forks? && children_being_extracted?
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
    data[:audit_from] = Audit.context[:from]
    data[:link_to_network] = FeatureFlag.vexi.enabled_or_raise?(:extract_link_to_network, repository) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  job_start

  step :identify_repos do
    data[:repos_to_extract] = [repository.id]
    data[:repos_to_extract] += repository.descendant_ids if include_forks?
  end

  # if something is wrong with the source file system, fail early.
  # git-janitor will look for common problems and if it cannot fix them, abort.
  step :janitor_fix do
    begin
      repos_to_extract.each do |repo|
        repo.janitor_fix
      end
    rescue GitRPC::CommandFailed, Repository::CommandFailed => e
      # `e.message` contains the command line arguments, the output, and the error. The command line and the output
      # contain the repository path already twice and this almost exceeds the maximum orchestration errors lenght of
      # 256 characters. Let's parse the actual error to store the relevant information in the database.
      err = e.message.match(/.*Error: (.+)/)
      return :failed, err ? err[1] : e.message
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
    garbage_collect(old_network, "garbage_collection")
  end

  step :prep_shared_storage do
    # the copy_fork and prepare_copy_fork steps below require the shared storage urls, so make sure they exist
    if data[:link_to_network]
      repos_to_extract.each { |r| link_to_network(r) }
    else
      repos_to_extract.each &:enable_or_disable_shared_storage
    end
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
      if data[:link_to_network]
        link_to_network(dup)
      else
        dup.enable_shared_storage
      end
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
    if FeatureFlag.vexi.enabled?(:repos_domain_reload, default: false)
      Repositories.domain.reload(repository)
    else
      repository.reload
    end
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
    remaining_repos = remaining_repos_to_extract

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
    ff = FeatureFlag.vexi.enabled?(:repos_domain_reload, default: false)
    repos_to_extract.each do |r|
      if ff
        T.cast(Repositories.domain.reload(r), Repository).sync_routes_from_network # rubocop:todo GitHub/AvoidCast
      else
        r.reload.sync_routes_from_network
      end
    end
    if ff
      Repositories.domain.reload(repository)
    else
      repository.reload
    end
  end

  step :compare_checksums do
    begin
      nw_reader = GitHub::DGit::Routing.preferred_reader_for_network(repository.network_id)
      out = GitHub::DGit::Maintenance.recompute_checksums(repository, nw_reader)
      checksum = out[:checksum]
      data[:dgit_checksum_after] = checksum

      if checksum.nil? && attempts < MAX_ATTEMPTS
        # Try a few times to get the checksum, but give up and move on before the framework fails the orchestration.
        # we don't need to log a warning here since the exception will be logged as a failed and retried step
        raise RetryStepError.new("dgit checksum is nil")
      end

      if data[:dgit_checksum_before] != data[:dgit_checksum_after]
        # log an error if the checksums don't match, but don't fail
        log_error("dgit checksums do not match")
        GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:compare_checksums.no_match"])
      end
    rescue GitHub::DGit::ChecksumInitError => e
      # this works on retry
      raise RetryStepError.new("DGit::ChecksumInitError")
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

  step :copy_media do
    # Begin copying media before deleting any repos to avoid a race condition where the
    # old network gets cleaned up due to a failing/stuck orchestration before the async copy can begin
    Media::Transition.async_copy(old_network, new_network)
  end

  step :delete_source_repos do
    if old_network.nil?
      GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:delete_source_repos.old_network_nil"])
      log_error("old network #{old_network_id} is gone")
      return
    end

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
        elsif !FeatureFlag.vexi.enabled_or_raise?(:extract_save_wiki) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
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

  step :enable_shared_storage do
    if data[:link_to_network]
      repos_to_extract.each { |r| link_to_network(r) }
    else
      repos_to_extract.each &:enable_or_disable_shared_storage
    end
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
    name = data[:audit_from]&.start_with?("stafftools") ? "staff.repo_#{action}" : "repo.#{action}"
    GitHub.instrument name, repo: repository, old_network_id: old_network_id
  end

  step :destroy_old_network do
    if attach? && old_network_id.present? && old_network.present?
      old_network.reparent_child_networks(new_network_id)
      if old_network.active_and_deleted_repositories.empty?
        old_network.destroy
        @old_network = nil
      end
    end
  end

  # this is a best-effort attempt to replace the old network
  # don't retry and don't fail if it fails
  step :garbage_collection_after_copy do
    garbage_collect(old_network, "garbage_collection_after_copy") if old_network.present?
  end

  # this is a best-effort attempt to repack the new network
  # don't retry and don't fail if it fails
  step :garbage_collection_new_network do
    garbage_collect(new_network, "garbage_collection_new_network")
  end

  step :calculate_network_counts do
    if FeatureFlag.vexi.enabled?(:repos_domain_reload, default: false)
      T.cast(Repositories.domain.reload(old_parent), Repository).calculate_network_counts! if old_parent # rubocop:todo GitHub/AvoidCast
      T.cast(Repositories.domain.reload(repository), Repository).calculate_network_counts! if attach? || !include_forks? # rubocop:todo GitHub/AvoidCast
    else
      old_parent.reload.calculate_network_counts! if old_parent
      repository.reload.calculate_network_counts! if attach? || !include_forks?
    end
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

  step :invalidate_caches do
    repository.invalidate_nwo_cache(Repositories::Cache::InvalidateOn::Extract)
  end

  ###############################################################################################

  sig { returns(Repository) }
  def repository
    T.must(super)
  end

  sig { params(network: RepositoryNetwork, step_name: String).void }
  def garbage_collect(network, step_name)
    begin
      network.rpc.nw_gc(geometric: false, auto: true)
    rescue GitRPC::CommandFailed, GitRPC::Protocol::DGit::ResponseError, GitRPC::Timeout, GitRPC::NetworkError, Twirp::Error => e
      GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:#{step_name}"])
      log_error("nw_gc failed: #{network.last_maintenance_at} #{e.message}")
    end
  end

  # Ensure the repo is network-linked by calling `rpc.nw_link` if necessary
  # This enables shared storage into the network.git folder
  sig { params(repo: Repository).void }
  def link_to_network(repo)
    repo.rpc.nw_link unless repo.rpc.nw_linked?
  end

  # Inspect a failed orchestration and determine if it can be retried
  # Returns true if it can be retried
  # Returns false and changes state to :abandoned, and updates the error_message if it cannot be retried
  sig { returns(T::Boolean) }
  def can_retry_failed_orchestration?
    # call the base class to do common checks
    return false unless base_can_retry_failed_orchestration?

    if step_name == "inspect_environment"
      # if we previously didn't get past the environment check, we can retry since the environment may have changed
      return true
    end

    # Make sure this repo hasn't already changed networks
    unless repository.network_id == old_network_id || repository.network_id == new_network_id
      end_orchestration(:abandoned, "repository is on an unexpected network")
      return false
    end

    if repository.network_id == old_network_id
      if old_network.nil?
        end_orchestration(:abandoned, "old network is gone")
        return false
      end

      if new_network_id && new_network.nil?
        # The new network once existed, but it's gone now.
        if attach?
          end_orchestration(:abandoned, "new network is gone so cannot attach")
          return false
        else
          # Our new network got cleaned up, so let's start over.
          # Start with the first step after :job_start
          index = self.class.all_steps.find_index { |s| s.name == :job_start } + 1
          first_step = self.class.all_steps[index].name
          if self.step_name != first_step
            self.step_name = first_step
            self.data[:new_network_id] = nil
            self.data[:repos_to_extract] = nil
            self.save!
          end
        end
      end
    end
    true
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

  # Find the repos we are extracting that haven't been moved to the new network yet
  def remaining_repos_to_extract
    Repository.where(id: data[:repos_to_extract], source_id: old_network_id)
  end

  # Create a dummy repo object on the new network, to be used for copying the repo contents
  def duplicate_repo_on_different_network(repo, network)
    dup = repo.dup

    dup.id = repo.id
    dup.raw_data = ""
    dup.network = network
    dup.reset_git_cache

    if FeatureFlag.vexi.enabled_or_raise?(:extract_wiki_fix) && repo.unsullied_wiki.exist? # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      dup.unsullied_wiki(true)
      dup.unsullied_wiki.reset_git_cache
    end

    # it is critical to reload the routes here so we don't manipulate the wrong network!
    dup.dgit_reload_routes!
    dup.set_rpc_network_override(network)

    if repo.unsullied_wiki.exist?
      unless FeatureFlag.vexi.enabled_or_raise?(:extract_wiki_fix) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
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

  def old_network_id
    data[:old_network_id]
  end

  def old_network
    @old_network ||= RepositoryNetwork.find_by(id: data[:old_network_id])
  end

  def old_parent
    @old_parent ||= if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
      Repositories.domain.by_id(data[:old_parent_id].to_i)
    else
      Repository.find_by(id: data[:old_parent_id])
    end
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

  sig { returns(T::Array[String]) }
  def logged_disallowed_concurrent_orchestration_types
    COMMON_DISALLOWED_CONCURRENT_ORCHESTRATIONS
  end

  sig { returns(T::Array[T.nilable(String)]) }
  def disallowed_concurrent_orchestration_types
    COMMON_DISALLOWED_CONCURRENT_ORCHESTRATIONS
  end
end
