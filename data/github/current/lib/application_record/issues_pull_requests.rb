# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class IssuesPullRequests < Base
    include GitHub::MaxExecutionTime

    self.abstract_class = true

    def self.cluster_name
      :"issues-pull-requests"
    end

    def self.dedicated_background_destroy_queue_name
      "background_destroy_#{cluster_name.to_s.underscore}".to_sym
    end

    if GitHub::AppEnvironment.development? && ENV["PARTITIONING_PULL_REQUESTS_CONNECTS_TO_SHARDS"] == "1"
      connects_to shards: {
        shard_0: { writing: :issues_pull_requests_primary, reading: :issues_pull_requests_primary, reading_slow: :issues_pull_requests_primary },
        shard_1: { writing: :issues_pull_requests_by_repo_owner_shard_one_primary, reading: :issues_pull_requests_by_repo_owner_shard_one_primary, reading_slow: :issues_pull_requests_by_repo_owner_shard_one_primary }
      }
    elsif ENV["LUC_PERFORMANCE"] == "1" && ENV["PARTITIONING_PULL_REQUESTS_CONNECTS_TO_SHARDS"] == "1"
      connects_to shards: {
        shard_0: { writing: :issues_pull_requests_primary, reading: :issues_pull_requests_readonly, reading_slow: :issues_pull_requests_readonly_slow },
        shard_1: { writing: :issues_pull_requests_primary, reading: :issues_pull_requests_by_repo_owner_shard_one_readonly, reading_slow: :issues_pull_requests_by_repo_owner_shard_one_readonly_slow }
      }
    else
      connects_to database: {
        writing: :issues_pull_requests_primary,
        reading: :issues_pull_requests_readonly,
        reading_slow: :issues_pull_requests_readonly_slow
      }
    end
  end
end
