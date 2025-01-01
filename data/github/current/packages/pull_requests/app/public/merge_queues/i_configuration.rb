# typed: strict
# frozen_string_literal: true

module MergeQueues
  module IConfiguration
    extend T::Helpers
    extend T::Sig

    interface!

    # The amount of time to wait before ignoring the #min_merge_entries_size
    # value and merging a collection of entries smaller than the customer
    # desires.
    sig { abstract.returns(ActiveSupport::Duration) }
    def max_wait_for_min_merge_entries_size; end

    # Minimum amount of entries to be merged in a single batch. This is a
    # "soft" guideline as we will ignore these in situations where we may have
    # halting problems due to low volumes of merging.
    sig { abstract.returns(Integer) }
    def min_merge_entries_size; end

    # Maxmimum number of entries to merge in a single batch.
    sig { abstract.returns(Integer) }
    def max_merge_entries_size; end

    # Maximum number of concurrent Checks at once.
    sig { abstract.returns(Integer) }
    def max_concurrency; end

    # Maximum number of times we will retry checks before marking the entry as
    # failed.
    sig { abstract.returns(Integer) }
    def max_attempts; end

    # Flag that determines if the User will control the merging or not. When
    # enabled, all merging occurs through the API.
    sig { abstract.returns(T::Boolean) }
    def actor_controlled_merging; end

    # Maximum time to wait for checks
    sig { abstract.returns(ActiveSupport::Duration) }
    def check_response_timeout; end

    # Strategy for deciding which entries get merged together, e.g. require all
    # entries to be green, or allow failing entries to merge if they are
    # followed by at least one passing entry.
    sig { abstract.returns(GroupingStrategy) }
    def grouping_strategy; end

    # The merge method to use when merging entries.
    sig { abstract.returns(MergeMethod) }
    def merge_method; end
  end
end
