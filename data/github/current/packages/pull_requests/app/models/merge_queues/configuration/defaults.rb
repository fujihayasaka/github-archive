# typed: strict
# frozen_string_literal: true

module MergeQueues
  class Configuration
    class Defaults
      include IConfiguration

      sig { override.returns(ActiveSupport::Duration) }
      def max_wait_for_min_merge_entries_size = 5.minutes

      sig { override.returns(Integer) }
      def min_merge_entries_size = 1

      sig { override.returns(Integer) }
      def max_merge_entries_size = 5

      sig { override.returns(Integer) }
      def max_concurrency = 5

      sig { override.returns(Integer) }
      def max_attempts = 0

      sig { override.returns(T::Boolean) }
      def actor_controlled_merging = false

      sig { override.returns(ActiveSupport::Duration) }
      def check_response_timeout = 1.hour

      sig { override.returns(IConfiguration::GroupingStrategy) }
      def grouping_strategy = IConfiguration::GroupingStrategy::AllGreen

      sig { override.returns(IConfiguration::MergeMethod) }
      def merge_method = IConfiguration::MergeMethod::Merge
    end
  end
end
