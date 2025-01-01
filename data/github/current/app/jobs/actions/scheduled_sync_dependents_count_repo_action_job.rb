# typed: false
# frozen_string_literal: true

module Actions
  class ScheduledSyncDependentsCountRepoActionJob < BatchedJob
    BATCH_SIZE = 30
    RETRY_COUNT_FOR_DEPENDENTS_API = 2
    queue_as :repository_actions_update
    schedule interval: 1.day, condition: -> { !GitHub.enterprise? }
    retry_on_dirty_exit

    def perform(*args, initial_start: Time.now.utc, offset_item_id: 0, progress: 0, **options)
      return unless GitHub.flipper[:enable_sync_dependents_count_repo_action_job].enabled?
      super
    end

    def next_batch(offset_item_id: 0, **options)
      GitHub::Logger.log({
        message: "Fetching the next batch of repository_actions",
        fn: "ScheduledSyncDependentsCountRepoActionJob.next_batch",
        offset_item_id: offset_item_id,
      })

      RepositoryAction.listed
        .where("id > ?", offset_item_id)
        .order(id: :asc)
        .limit(BATCH_SIZE)
    end

    def process_batch(repository_actions_batch, *args, **options)
      return if repository_actions_batch.empty?

      repository_actions_batch.each do |repository_action|
        repository = Repository.find_by(id: repository_action.repository_id)
        next if repository.nil? || !repository.dependency_graph_enabled?

        dependents_count = get_dependents_count(repository_action.repository_id, repository.name_with_display_owner)
        update_repository_actions_dependents_count(repository_action, dependents_count)
      end
    end

    def update_repository_actions_dependents_count(repository_action, dependents_count)
      begin
        return if dependents_count.nil? || dependents_count == repository_action.dependents_count

        with_write { repository_action.update(dependents_count: dependents_count) }

        GitHub.dogstats.increment("repository_actions.dependents_count.updated", tags: ["updated_by:scheduled_job"])
        GitHub::Logger.log({
          message: "Updated the dependents count",
          fn: "ScheduledSyncDependentsCountRepoActionJob.update_repository_actions_dependents_count",
          repository_id: repository_action.repository_id,
          dependents_count: dependents_count,
        })
      rescue Exception => error # rubocop:todo Lint/GenericRescue
        GitHub::Logger.log_exception({
          job: ScheduledSyncDependentsCountRepoActionJob.name,
          fn: "ScheduledSyncDependentsCountRepoActionJob.update_repository_actions_dependents_count",
          log_message: "Error updating the dependents_count for the repository_action #{error.message}",
          repository_id: repository_action.repository_id,
        }, error)
        Failbot.report(error, job: ScheduledSyncDependentsCountRepoActionJob.name)
      end
    end

    def get_dependents_count(repository_id, action_name_with_display_owner)
      dependent_type = PlatformTypes::DependencyGraphDependentType::REPOSITORY
      dependents_filter = { type: dependent_type.to_s.downcase.to_sym }

      begin
        retries ||= 0
        results = Platform::Loaders::Dependencies.load_packages({
          package_filter: {
            repository_id: repository_id,
            package_manager: "ACTIONS",
            names: action_name_with_display_owner,
            limit: 1,
          },
          dependents_filter: dependents_filter,
          include_dependents: false,
          include_dependent_counts: true,
        }).sync

        return results.value!.first&.repository_dependents_count
      rescue DependencyGraph::Client::TimeoutError => error
        retry if (retries += 1) < RETRY_COUNT_FOR_DEPENDENTS_API

        GitHub::Logger.log_exception({
          job: ScheduledSyncDependentsCountRepoActionJob.name,
          fn: "ScheduledSyncDependentsCountRepoActionJob.get_dependents_count",
          log_message: "DependencyGraph::Client::TimeoutError #{error.message}",
          repository_id: repository_id,
          retry_count: retries,
        }, error)
      rescue DependencyGraph::Client::ServiceUnavailableError => error
        GitHub::Logger.log_exception({
          job: ScheduledSyncDependentsCountRepoActionJob.name,
          fn: "ScheduledSyncDependentsCountRepoActionJob.get_dependents_count",
          log_message: "DependencyGraph::Client::ServiceUnavailableError #{error.message}",
          repository_id: repository_id,
          retry_count: retries,
        }, error)
      rescue => error # rubocop:todo Lint/GenericRescue
        GitHub::Logger.log_exception({
          job: ScheduledSyncDependentsCountRepoActionJob.name,
          fn: "ScheduledSyncDependentsCountRepoActionJob.get_dependents_count",
          repository_id: repository_id,
          retry_count: retries,
        }, error)
      end

      nil
    end
  end
end
