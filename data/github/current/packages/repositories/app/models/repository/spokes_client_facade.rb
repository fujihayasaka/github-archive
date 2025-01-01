# typed: true
# frozen_string_literal: true

class Repository::SpokesClientFacade

  def initialize(repository)
    @repository = repository
  end

  attr_reader :repository

  def create_repository(skip_init: false)
    repository.network.initialize_placeholder_network_replicas

    repository.initialize_replicas_from_network

    if !repository.exists_on_disk?
      repository.setup_new_git_repository(skip_init: skip_init)
    end

    GitHub.dogstats.increment("spokes_client_create.success", tags: ["action:create"])
    true
  rescue => e # rubocop:todo Lint/RescueException
    Failbot.report(e, "code.function": "SpokesClientFacade#create_repository")
    GitHub.dogstats.increment("spokes_client_create.failure", tags: ["action:create"])
    false
  end

  def initialize_repository
    repository.initialize_git_repository_templates
    repository.update_pushed_at Time.now
    repository.async_backup
    GitHub.dogstats.increment("spokes_client_initialize.success")
    true
  rescue => e # rubocop:todo Lint/RescueException
    Failbot.report(e, "code.function": "SpokesClientFacade#initialize_repository")
    GitHub.dogstats.increment("spokes_client_initialize.failure")
    false
  end

  def clone_repository(source_repository:)
    repository.network.initialize_placeholder_network_replicas

    repository.initialize_replicas_from_network

    if !repository.exists_on_disk? && source_repository
      RepositoryCloneJob.perform_later(source_repository, repository)
    end

    GitHub.dogstats.increment("spokes_client_create.success", tags: ["action:clone"])
    true
  rescue => e # rubocop:todo Lint/RescueException
    Failbot.report(e, "code.function": "SpokesClientFacade#clone_repository")
    GitHub.dogstats.increment("spokes_client_create.failure", tags: ["action:clone"])
    false
  end

  # Performs all necessary steps to remove the repository from the spokes perspective:
  # - Remove the repository from disk, this also removes the network if the repository is the last in its network
  # - Remove the repository wiki from disk
  # - Remove the repository replicas and checksums from the spokes database
  # - Remove the network replicas from the spokes database (if the repository is last in its network)
  #
  # Returns true if removing from disk succeeds, false if removing the repo or its wiki fails
  def purge_repository
    begin
      repository.remove_from_disk
      repository.remove_wiki_from_disk unless repository.network.nil?
    rescue GitHub::DGit::NotFoundError, GitHub::DGit::UnroutedError
      purge_replicas!
      raise
    end

    purge_replicas!
    GitHub.dogstats.increment("spokes_client_purge.success")
    true

  rescue => e # rubocop:todo Lint/RescueException
    Failbot.report(e, "code.function": "SpokesClientFacade#purge_repository")
    GitHub.dogstats.increment("spokes_client_purge.failure")
    false
  end

  def purge_from_disk!
    repository.remove_from_disk
    repository.remove_wiki_from_disk unless repository.network.nil?
  rescue GitHub::DGit::NotFoundError, GitHub::DGit::UnroutedError
    nil
  end

  def purge_replicas!
    if !repository.network.nil?
      GitHub::DGit::Maintenance.delete_repo_replicas_and_checksums(repository.network.id, repository.id)
      if repository.network.repositories.empty? && repository.network.deleted_repositories.count == 1
        GitHub::DGit::Maintenance.delete_network_replicas(repository.network.id)
      end
    end
  end
end
