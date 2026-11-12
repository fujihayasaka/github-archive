# frozen_string_literal: true

require "ecosystems"

class UpdateGraphEventHandler
  def self.run(message)
    owner = ::HydroHandlers::GitHub::User.from_message(message)
    repository = ::HydroHandlers::GitHub::Repository.from_message(message, owner: owner)
    graph_changes = ::HydroHandlers::DependencyGraph::GraphChanges.from_message(message)
    event_id = message.value[:event_id]

    new(
      owner:,
      repository:,
      graph_changes:,
      event_id:,
    ).run
  end

  def initialize(owner:, repository:, graph_changes:, event_id: nil)
    @owner = owner
    @repository = repository
    @graph_changes = graph_changes
    @event_id = event_id
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

    graph_changes.group_by(&:package_manager).each do |package_manager, changes|
      if package_manager.nil?
        Dependabot::Logger.warn(
          msg: "Unknown ecosystem in graph change, skipping",
          "gh.owner.id": owner.id,
          "gh.repo.id": repository.id,
        )
        next
      end

      directories = changes.map(&:directory)
      ref_name = changes.first.ref_name.presence
      commit_oid = changes.first.commit_oid.presence
      update_configs_and_directories = FindOrCreateUpdateConfigsForRun.new(
        repo:,
        package_manager: resolve_package_manager(repo, package_manager, directories, ref_name, commit_oid),
        directories: Directories.new(directories),
        user: owner,
        target_branch: branch_for(ref_name),
      ).run
      update_configs_and_directories.each do |update_config, dirs|
        enqueue_update_job(update_config, directories: dirs)
      end
    end
  end

  private

  attr_reader :owner, :repository, :graph_changes, :event_id

  def github_request_id
    return unless event_id&.nonzero?

    event_id
  end

  def onboard_new_repository
    UpdateGraph::OnboardRepositoryJob.perform_later(
      owner: owner,
      repository: repository,
      graph_changes: graph_changes,
      event_id: event_id,
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
      github_request_id:,
    )
  end

  def branch_for(ref_name)
    return nil if ref_name.nil?

    case ref_name
    when %r{\Arefs/heads/}
      ref_name.delete_prefix("refs/heads/")
    when %r{\Arefs/}
      nil
    else
      ref_name
    end
  end

  def resolve_package_manager(repo, package_manager, directories, ref_name, commit_oid = nil)
    ref = if commit_oid.present? &&
             repo.account&.monolith_feature_enabled?(:dependabot_use_commit_oid_for_pm_resolution)
            commit_oid
          else
            ref_name
          end

    EcosystemFileDetector.resolve_package_manager(
      package_manager:,
      account: repo.account,
      repo_id: repo.github_id,
      directories:,
      ref: ref,
      metric_prefix: "consumer.update_graph_event",
    )
  end
end
