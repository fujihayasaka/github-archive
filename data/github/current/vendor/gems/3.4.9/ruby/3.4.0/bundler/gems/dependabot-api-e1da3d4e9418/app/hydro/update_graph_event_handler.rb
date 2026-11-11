# frozen_string_literal: true

require "ecosystems"

class UpdateGraphEventHandler
  def self.run(message)
    owner = ::HydroHandlers::GitHub::User.from_message(message)
    repository = ::HydroHandlers::GitHub::Repository.from_message(message, owner: owner)
    graph_changes = ::HydroHandlers::DependencyGraph::GraphChanges.from_message(message)

    new(
      owner:,
      repository:,
      graph_changes:,
    ).run
  end

  def initialize(owner:, repository:, graph_changes:)
    @owner = owner
    @repository = repository
    @graph_changes = graph_changes
  end

  def run
    Dependabot::Exceptions.push(
      "gh.owner.id": owner.id,
      "gh.repo.id": repository.id,
    )

    if repository.exists?
      unless account&.active?
        Dependabot::Logger.info(
          msg: "Account is not active, skipping graph update",
          "gh.owner.id": owner.id,
          "gh.repo.id": repository.id,
        )
        return
      end

      create_graph_update_job
    else
      onboard_new_repository
    end
  end

  def create_graph_update_job # rubocop:disable Metrics/MethodLength
    repo = repository.create_repo!

    # group graph changes by ecosystem and collect all "directory" into directories
    data = {}
    graph_changes.each do |change|
      if change.package_manager.nil?
        Dependabot::Logger.warn(
          msg: "Unknown ecosystem in graph change, skipping",
          "gh.owner.id": owner.id,
          "gh.repo.id": repository.id,
        )
        next
      end

      data[change.package_manager] ||= []
      data[change.package_manager] << change.directory
    end

    data.each do |package_manager, needed_directories|
      update_configs_and_directories = FindOrCreateUpdateConfigsForRun.new(
        repo:,
        package_manager:,
        directories: Directories.new(needed_directories),
        user: owner,
      ).run
      update_configs_and_directories.each do |update_config, directories|
        enqueue_update_job(update_config, directories: directories)
      end
    end
  end

  private

  attr_reader :owner, :repository, :graph_changes

  def onboard_new_repository
    UpdateGraph::OnboardRepositoryJob.perform_later(
      owner: owner,
      repository: repository,
      graph_changes: graph_changes,
    )

    MetricsClient.increment(
      "consumer.repository_onboarded",
      tags: {
        trigger: "dependency_graph",
      }
    )
  end

  def account
    return @account if defined?(@account)

    @account = Account.find_by(github_id: owner.id)
  end

  def enqueue_update_job(update_config, directories:)
    CreateGraphUpdateJob.perform_later(
      update_config:,
      directories:,
    )
  end
end
