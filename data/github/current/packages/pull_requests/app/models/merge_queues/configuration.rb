# typed: strict
# frozen_string_literal: true

module MergeQueues
  # Customer configurable values for the MergeQueue.
  class Configuration < T::Struct
    include IConfiguration

    # The amount of time to wait before ignoring the #min_merge_entries_size value and merging a collection of entries
    # smaller than the customer desires.
    const :max_wait_for_min_merge_entries_size, ActiveSupport::Duration

    # Minimum amount of entries to be merged in a single batch. This is a "soft" guideline as we will ignore these
    # in situations where we may have halting problems due to low volumes of merging.
    const :min_merge_entries_size, Integer

    # Maxmimum number of entries to merge in a single batch.
    const :max_merge_entries_size, Integer

    # Maximum number of concurrent Checks at once.
    const :max_concurrency, Integer

    # Maximum number of times we will retry checks before marking the entry as failed.
    const :max_attempts, Integer

    # Flag that determines if the User will control the merging or not. When enabled, all merging occurs through the API.
    const :actor_controlled_merging, T::Boolean

    # Maximum time to wait for checks
    const :check_response_timeout, ActiveSupport::Duration

    # Strategy for deciding which entries get merged together, e.g. require all
    # entries to be green, or allow failing entries to merge if they are
    # followed by at least one passing entry.
    const :grouping_strategy, GroupingStrategy, default: GroupingStrategy::AllGreen

    # The merge method to use when merging entries.
    const :merge_method, MergeMethod, default: MergeMethod::Merge
  end
end
