# typed: false
# frozen_string_literal: true

# A good description of what happens from the git-systems perspective can be found here:
# https://github.com/github/github/blob/master/git-bin/git-copy-fork
class ExtractRepositoryOrchestration < RepositoryOrchestration
  step :inspect_environment do
    return :failed, "no existing network" if repository.network.nil?
    return :skipped, "single repo network" if new_network_id.nil? && repository.network&.repositories.count == 1
    return :failed, "same network" if new_network_id == repository.network.id
    return :failed, "missing storage" unless repository.exists_on_disk?
    return :failed, "already the root" if repository.network_root? && !attach?
    return :failed, "not enough disk space available" unless repository.network.enough_space_to_extract?(repository)
    if new_network
      # compare visibility, treating Internal as Private
      return :failed, "Cannot extract into a network with different visiblity" if new_network.root.public? != repository.public?
    end
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
    data[:network_size] = repository.network.repositories.size
    data[:new_extract] = true if new_extract?
  end

  job_start

  # before creating the new network, verify the old network is healthy enough to proceed
  # by running garbage collection and janitor. To do this we also need to identify the
  # repos to extract earlier than the previous version.
  step :garbage_collection do
    return unless new_extract?

    old_network.rpc.nw_gc(geometric: false)
  end

  step :identify_repos do
    return unless new_extract?

    @repos_to_extract = repository.repository_and_descendants
    data[:repos_to_extract] = repos_to_extract.map(&:id)
  end

  # if something is wrong with the source file system, fail early.
  # git-janitor will look for common problems and if it cannot fix them, abort.
  step :janitor_fix do
    return unless new_extract?

    begin
      repos_to_extract.each do |repo|
        repo.janitor_fix unless repo.network_root?
      end
    rescue GitRPC::CommandFailed, Repository::CommandFailed => e
      # don't fail if janitor fails. Some errors are not critical.
      log_error("janitor_fix failed with: #{e.message}")
      GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:janitor_fix"])
    end
  end

  # If there are unknown/unexpected files that we don't know what to do with, fail early.
  # We'll need to figure out what to do with the unknown file types and
  # update git-copy-fork or git-janitor to handle them.
  # see https://github.com/github/github/blob/master/git-bin/git-copy-fork
  # and https://github.com/github/gitrpcd/blob/main/janitor/policy.go
  step :find_unknown_files do
    return unless new_extract?

    repos_to_extract.each do |repo|
      out = repo.rpc.unknown_files
      # we need to fail here and update git-copy-forks to handle the unknown files before allowing this extraction to proceed
      return :failed, "found unknown files: #{out}" if out
    end
  end

  step :prep_shared_storage do
    return unless new_extract?

    # the copy_fork and prepare_copy_fork steps below require the shared storage urls, so make sure they exist
    repos_to_extract.each &:enable_or_disable_shared_storage

    # record the dgit checksum for validation later
    begin
      nw_reader = GitHub::DGit::Routing.preferred_reader_for_network(repository.network_id)
      out = GitHub::DGit::Maintenance.recompute_checksums(repository, nw_reader)
      # production has :checksum, codespace has :repo
      data[:dgit_checksum_before] = out[:checksum] || out[:repo]
    rescue GitHub::DGit::ThreepcFailedToLock => e
      # don't fail if we can't get the checksum
      # retries don't seem to help so just move on
      log_error("Failed to get dgit_checksum_before. #{e.message}")
      GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:prep_shared_storage"])
    end
  end

  step :create_new_network do
    # new_network may already exist in Attach scenarios, or if this step is re-executed
    return if new_network.present?
    @new_network = repository.network.children.create!(root: repository)
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

  step :identify_repos_to_extract do
    return if new_extract? # this was already done earlier

    @repos_to_extract = repository.repository_and_descendants
    data[:repos_to_extract] = repos_to_extract.map(&:id)
  end

  step :prepare_new_file_system do
    return unless new_extract?

    repos_to_extract.each do |repo|
      dup = duplicate_repo_on_different_network(repo, new_network)

      # if this is a broken extract + reattach scenario, try to delete any remnants in the new repo
      if dup.rpc.exist?
        dup.remove_from_disk
        dup.remove_wiki_from_disk
        # remove_from_disk can flake in tests with `eval error: repository <id> not found`
        # so call rpc.remove too
        dup.rpc.remove
      end

      # setup an empty #{repo.network_id}/#{repo.id}.git
      dup.create_git_repository_on_disk

      if dup.has_wiki? && dup.unsullied_wiki
        creator =
          GitHub::RepoCreator.new(dup.unsullied_wiki,
            public: dup.public?,
            template: GitHub.repository_template,
            nwo: "#{dup.name_with_display_owner}.wiki")
        creator.init
      end
      dup.initialize_git_repository_templates
      dup.enable_shared_storage
    end
  end

  # prepare_copy_fork copies the network files, so is the bulk of the copy.
  # This can be done while the repos are unlocked.
  step :prepare_copy_forks do
    return unless new_extract?

    repo_list = repo_and_wiki_ids(repos_to_extract)
    new_network.rpc.prepare_copy_fork(old_network.shared_storage_url, repo_list)
  end

  step :lock_repos do
    return unless new_extract?

    repos_to_extract.each do |repo|
      repo.lock_for_move
    end
  end

  step :copy_forks do
    return unless new_extract?

    # Re-evaluate what repos need to be extracted each time we run this step.
    # Some may have already been extracted in a previous run and we don't want to re-copy them.
    remaining_repos = remaining_repos_to_extract(repository, [])

    remaining_repos.each do |repo|
      new_network.rpc.copy_fork(old_network.shared_storage_url, "#{repo.id}")
      if repo.wiki_exists_on_disk?
        new_network.rpc.copy_fork(old_network.shared_storage_url, "#{repo.id}.wiki")
      end

      # point the repo at the new network
      repo.set_network(new_network)
      repo.save!
    end
  end

  step :detach_from_parent do
    return unless new_extract?

    # This orchestration is for both Extract and Attach, and the new parent is not nil in Attach scenarios
    new_parent_id = attach? ? new_network&.root_id : nil
    repository.update!(parent_id: new_parent_id)
  end

  step :sync_org_owned_private_network_with_forks do
    return unless new_extract?

    old_network&.reload&.sync_org_owned_private_network_with_forks
    new_network&.reload&.sync_org_owned_private_network_with_forks
  end

  step :move_files_on_disk do
    return if new_extract?

    old_network.move_repositories_into_network(repos_to_extract, new_network)
  end

  step :update_network_and_parents, transaction: true do
    return if new_extract?

    Repository.where(id: data[:repos_to_extract]).update_all(source_id: new_network.id)
    new_parent_id = new_network&.root_id == repository.id ? nil : new_network&.root_id
    Repository.where(id: repository.id).update_all(parent_id: new_parent_id)

    old_network&.sync_org_owned_private_network_with_forks
    new_network&.reload.sync_org_owned_private_network_with_forks

    # flush our cache since the repos got updated in the database
    @repos_to_extract = nil

    repos_to_extract.each do |r|
      r.unlock_including_descendants! unless r.locked_on_billing?
      r.update_organization
    end
    new_network.update_permissions_on(repos_to_extract, old_organization)
  end

  step :resync_forks do
    repos_to_extract.each do |r|
      r.reload.sync_routes_from_network
    end
    repository.reload
  end

  step :copy_default_branch do
    return unless new_extract?

    # flush our cache since the database records have changed with new source_ids and root parent_id
    @repos_to_extract = nil

    # because copy_fork behaves like a fetch and not a clone, we need to update the default branch ourselves
    repos_to_extract.each do |repo|
      dup = duplicate_repo_on_different_network(repo, old_network)

      if repo.default_branch != dup.default_branch
        repo.update_default_branch(dup.default_branch)
      end

      if repo.reload.default_branch != dup.default_branch
        raise RetryStepError.new("default_branch does not match: #{repo.default_branch} != #{dup.default_branch}")
      end
    end
  end

  step :unlock_repos do
    return unless new_extract?

    repos_to_extract.each do |r|
      r.unlock_including_descendants! unless r.locked_on_billing?
    end
  end

  step :compare_checksums do
    return unless new_extract?

    begin
      nw_reader = GitHub::DGit::Routing.preferred_reader_for_network(repository.network_id)
      out = GitHub::DGit::Maintenance.recompute_checksums(repository, nw_reader)
      # production has :checksum, codespace has :repo
      checksum = out[:checksum] || out[:repo]
      data[:dgit_checksum_after] = checksum

      if checksum.nil?
        GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:compare_checksums"])
        raise RetryStepError.new("dgit checksum is nil")
      end

      if data[:dgit_checksum_before] != data[:dgit_checksum_after]
        # log an error if the checksums don't match, but don't fail
        log_error("dgit checksums do not match")
        GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:compare_checksums"])
      end
    rescue GitHub::DGit::ThreepcFailedToLock => e
      # don't fail if we can't get the checksum
      # retries don't seem to help here, so just move on
      GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:compare_checksums"])
      log_error("Failed to get dgit_checksum_after. #{e.message}")
    end
  end

  step :delete_source_repos do
    return unless new_extract?

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
      dup.remove_wiki_from_disk
      dup.rpc.remove # avoid flaky tests
    end
  end

  step :update_organization do
    return unless new_extract?

    repos_to_extract.each do |r|
      r.update_organization
    end
    new_network.update_permissions_on(repos_to_extract, old_organization)
  end

  step :async_copy_media do
    Media::Transition.async_copy(old_network, new_network)
  end

  step :check_disk_1 do
    return unless new_extract?

    @repos_to_extract = nil

    repos_to_extract.each do |repo|
      unless repo.exists_on_disk?
        GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:check_disk_1"])
        log_error("repo #{repo.dgit_spec} does not exist on disk")
      end
    end
  end

  step :enable_shared_storage do
    repos_to_extract.each &:enable_or_disable_shared_storage
  end

  step :reload_private_repos do
    repository.owner.owned_private_repositories.reload
  end

  step :dgit_reload_routes do
    repository.dgit_reload_routes!
  end

  step :touch_repo do
    repository.touch
  end

  step :audit_logs do
    name = Audit.context[:from]&.start_with?("stafftools") ? "staff.repo_extract" : "repo.extract"
    GitHub.instrument name, repo: repository, old_network_id: old_network&.id
  end

  step :destroy_old_network do
    if attach?
      old_network.reparent_child_networks(new_network_id)
      if old_network.repositories.count == 0 && old_network.deleted_repositories.count == 0
        old_network.destroy
        @old_network = nil
      end
    end
  end

  step :check_disk_2 do
    return unless new_extract?

    @repos_to_extract = nil

    repos_to_extract.each do |repo|
      unless repo.exists_on_disk?
        GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:check_disk_2"])
        log_error("repo #{repo.dgit_spec} does not exist on disk")
      end
    end
  end

  # this is a best-effort attempt to clean up the remaining networks
  # don't retry and don't fail if it fails
  step :garbage_collection_after_copy do
    return unless new_extract?

    begin
      old_network.rpc.nw_gc(geometric: false) if old_network.present?
    rescue GitRPC::CommandFailed, GitRPC::Protocol::DGit::ResponseError
      GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:garbage_collection_after_copy"])
    end
  end

  # this is a best-effort attempt to clean up the remaining networks
  # don't retry and don't fail if it fails
  step :garbage_collection_new_network do
    return unless new_extract?

    begin
      new_network.rpc.nw_gc(geometric: false)
    rescue GitRPC::CommandFailed, GitRPC::Protocol::DGit::ResponseError
      GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:garbage_collection_new_network"])
    end
  end

  step :calculate_network_counts do
    old_parent.reload.calculate_network_counts! if old_parent
    repository.reload.calculate_network_counts! if attach?
  end

  step :reindex_network do
    if attach? || data[:reindex]
      repository.reindex_after_network_operation(data[:was_root], data[:was_fork], old_network)
    end
  end

  step :check_disk do
    return unless new_extract?

    missing_repos = 0
    repos_to_extract.each do |repo|
      unless repo.exists_on_disk?
        GitHub.dogstats.increment("repository_orchestration.step.warning", tags: ["type:ExtractRepositoryOrchestration", "step:check_disk"])
        log_error("repo #{repo.dgit_spec} does not exist on disk")
        missing_repos += 1
      end
    end

    if missing_repos > 0
      # turn off the :new_extract FF so we don't break any more repos
      GitHub.flipper[:new_extract].disable
      log_error("Disabled the :new_extract FF")

      return :failed, "missing #{missing_repos} repos"
    end
  end

  step :publish_extracted do
    message = build_hydro_event_message.merge({
      was_root: data[:was_root],
      was_fork: data[:was_fork],
      old_network_id: data[:old_network_id],
      old_parent_id: data[:old_parent_id],
      old_organization_id: data[:old_organization_id],
      network_size: data[:network_size]
    })
    publish_hydro_event(schema: "github.repositories.v1.Extracted", message:)
  end

  ###############################################################################################

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
    dup.dgit_reload_routes!
    dup.set_rpc_network_override(network)

    if repo.unsullied_wiki.exist?
      dup.unsullied_wiki(true)
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
    @new_network ||= RepositoryNetwork.find_by_id(new_network_id) if new_network_id
  end

  def old_network
    @old_network ||= RepositoryNetwork.find_by_id(data[:old_network_id])
  end

  def old_parent
    @old_parent ||= Repository.find_by_id(data[:old_parent_id])
  end

  def repos_to_extract
    @repos_to_extract ||= Repository.where(id: data[:repos_to_extract]).order(:id).to_a
  end

  def old_organization
    @old_organization ||= Organization.find_by_id(data[:old_organization_id])
  end

  def attach?
    data[:attach].present?
  end

  def new_extract?
    return @new_extract if defined?(@new_extract)
    @new_extract = data[:new_extract].present? || repository.feature_enabled?(:new_extract)
  end
end
