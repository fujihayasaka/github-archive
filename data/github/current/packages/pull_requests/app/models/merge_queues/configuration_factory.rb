# typed: strict
# frozen_string_literal: true

module MergeQueues
  # Responsible for building a Configuration instance for a given MergeQueue.
  class ConfigurationFactory
    sig { params(merge_queue: MergeQueue).returns(IConfiguration) }
    def self.build(merge_queue)
      Configuration.new(
        actor_controlled_merging: merge_queue.actor_controlled_merging?,
        merge_method: IConfiguration::MergeMethod.deserialize(merge_queue.merge_method),
        max_concurrency: merge_queue.max_entries_to_build,
        max_attempts: merge_queue.check_run_retries_limit,
        max_wait_for_min_merge_entries_size: merge_queue.min_entries_to_merge_wait_minutes.minutes,
        min_merge_entries_size: merge_queue.min_entries_to_merge,
        max_merge_entries_size: merge_queue.max_entries_to_merge,
        check_response_timeout: merge_queue.check_response_timeout_minutes.minutes == 0 ? 1.minute : merge_queue.check_response_timeout_minutes.minutes,
        grouping_strategy: IConfiguration::GroupingStrategy.deserialize(merge_queue.merging_strategy),
      )
    end
  end
end
