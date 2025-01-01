# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

module Actions
  class ScheduledSyncDependentsCountRepoActionUsingBatchDgApiJob < BatchedJob
    class RepositoryActionsMetadata
      attr_reader :repository_action, :action_name_with_display_owner

      def initialize(repository_action, action_name_with_display_owner)
        @repository_action = repository_action
        @action_name_with_display_owner = action_name_with_display_owner
      end
    end

    BATCH_SIZE = 30
    RETRY_COUNT_FOR_DEPENDENTS_API = 2
    API_BATCH_SIZE = 10
    queue_as :repository_actions_update
    schedule interval: 1.day, condition: -> { !GitHub.enterprise? }
    retry_on_dirty_exit

    def next_batch(offset_item_id: 0, **options)
      GitHub::Logger.log({
        message: "Fetching the next batch of repository_actions",
        fn: "ScheduledSyncDependentsCountRepoActionUsingBatchDgApiJob.next_batch",
        offset_item_id: offset_item_id,
      })

      RepositoryAction.listed
        .where("id > ?", offset_item_id)
        .order(id: :asc)
        .limit(BATCH_SIZE)
    end

    def process_batch(repository_actions_batch, *args, **options)
      return if repository_actions_batch.empty?

      repository_actions_batch.each_slice(API_BATCH_SIZE) do |repository_actions_batch_slice|
        process_repository_actions(repository_actions_batch_slice)
      end
    end

    def process_repository_actions(repository_actions)
      repository_action_metadata_list = get_repo_action_details(repository_actions)
      return if repository_action_metadata_list.empty?

      repo_id_list = repository_action_metadata_list.collect { |metadata| metadata.repository_action.repository_id }
      action_name_with_display_owner_list = repository_action_metadata_list.collect(&:action_name_with_display_owner)

      dependents_count_results = get_dependents_result_for_batch(repo_id_list, action_name_with_display_owner_list)
      return if dependents_count_results.nil?

      RepositoryAction.throttle do
        repository_action_metadata_list.each do |metadata|
          dependents_count = get_repo_action_dependents_count(dependents_count_results, metadata.action_name_with_display_owner)
          update_repository_actions_dependents_count(metadata.repository_action, dependents_count)
        end
      end
    end

    def get_repo_action_details(repository_actions)
      repository_action_metadata_list = []
      repository_actions.each do |repository_action|
        repository = Repository.find_by(id: repository_action.repository_id)
        next if repository.nil?

        repository_action_metadata_list << RepositoryActionsMetadata.new(repository_action, repository.name_with_display_owner)
      end

      repository_action_metadata_list
    end

    def get_dependents_result_for_batch(repo_id_list, action_name_with_display_owner_list)
      dependent_type = PlatformTypes::DependencyGraphDependentType::REPOSITORY
      dependents_filter = { type: dependent_type.to_s.downcase.to_sym }

      begin
        retries ||= 0
        results = Platform::Loaders::Dependencies.load_packages({
          package_filter: {
            repository_id: repo_id_list,
            package_manager: "ACTIONS",
            names: action_name_with_display_owner_list,
            limit: repo_id_list.size,
          },
          dependents_filter: dependents_filter,
          include_dependents: false,
          include_dependent_counts: true,
        }).sync

        return results.value!
      rescue DependencyGraph::Client::TimeoutError => error
        retry if (retries += 1) < RETRY_COUNT_FOR_DEPENDENTS_API

        GitHub::Logger.log_exception({
          job: ScheduledSyncDependentsCountRepoActionUsingBatchDgApiJob.name,
          fn: "ScheduledSyncDependentsCountRepoActionUsingBatchDgApiJob.get_dependents_result_for_batch",
          log_message: "DependencyGraph::Client::TimeoutError #{error.message}",
          repo_ids: repo_id_list,
          retry_count: retries,
        }, error)
      rescue DependencyGraph::Client::ServiceUnavailableError => error
        GitHub::Logger.log_exception({
          job: ScheduledSyncDependentsCountRepoActionUsingBatchDgApiJob.name,
          fn: "ScheduledSyncDependentsCountRepoActionUsingBatchDgApiJob.get_dependents_result_for_batch",
          log_message: "DependencyGraph::Client::ServiceUnavailableError #{error.message}",
          repo_ids: repo_id_list,
          retry_count: retries,
        }, error)
      rescue => error # rubocop:todo Lint/GenericRescue
        GitHub::Logger.log_exception({
          job: ScheduledSyncDependentsCountRepoActionUsingBatchDgApiJob.name,
          fn: "ScheduledSyncDependentsCountRepoActionUsingBatchDgApiJob.get_dependents_result_for_batch",
          repo_ids: repo_id_list,
          retry_count: retries,
        }, error)
      end

      nil
    end

    def get_repo_action_dependents_count(results, action_name_with_display_owner)
      filtered_result = results.select { |dg_package| dg_package.name.casecmp?(action_name_with_display_owner) }
      filtered_result.first&.repository_dependents_count
    end

    def update_repository_actions_dependents_count(repository_action, dependents_count)
      begin
        return if dependents_count.nil? || dependents_count == repository_action.dependents_count

        with_write { repository_action.update(dependents_count: dependents_count) }

        GitHub.dogstats.increment("repository_actions.dependents_count.updated", tags: ["updated_by:batched_scheduled_job"])
        GitHub::Logger.log({
          message: "Updated the dependents count",
          fn: "ScheduledSyncDependentsCountRepoActionUsingBatchDgApiJob.update_repository_actions_dependents_count",
          repository_id: repository_action.repository_id,
          dependents_count: dependents_count,
        })
      rescue Exception => error # rubocop:todo Lint/GenericRescue
        GitHub::Logger.log_exception({
          job: ScheduledSyncDependentsCountRepoActionUsingBatchDgApiJob.name,
          fn: "ScheduledSyncDependentsCountRepoActionUsingBatchDgApiJob.update_repository_actions_dependents_count",
          log_message: "Error updating the dependents_count for the repository_action #{error.message}",
          repository_id: repository_action.repository_id,
        }, error)
        Failbot.report(error, job: ScheduledSyncDependentsCountRepoActionUsingBatchDgApiJob.name)
      end
    end
  end
end
