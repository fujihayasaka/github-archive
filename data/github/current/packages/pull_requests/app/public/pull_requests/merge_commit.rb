# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    sig { params(pull_request: PullRequest, priority: Symbol).void }
    def self.enqueue_create(pull_request:, priority: :low)
      return unless pull_request.open?
      return unless repository = pull_request.repository

      if repository.feature_flag_enabled?(:skip_cprmc_when_in_merge_queue, default: false)
        return if pull_request.in_merge_queue?
      end

      # currently_mergeable? is not a true predicate method and in this
      # particular scenario we are specifically interested in the nil state.
      # Therefore we need to do this somewhat awkward looking nil check
      # on a predicate method's return value.
      return unless pull_request.currently_mergeable?.nil?

      # If we have a pending ref update, skip enqueuing the job as it will boot and noop.
      exists = MergeCommitRequest.where(repository:, pull_request:).exists?
      GitHub.dogstats.increment("merge_commit.exists", tags: ["exists:#{exists}"])
      return if exists

      return unless repository_id = repository.id
      return unless pull_request_id = pull_request.id

      priority = case priority
      when :high
        Enums::Priority::High.serialize
      when :medium
        Enums::Priority::Medium.serialize
      else # includes :low
        Enums::Priority::Low.serialize
      end

      if repository.feature_flag_enabled?(:pull_request_stacks, default: false) && stack_id = pull_request.stack_entry&.stack_id
        CreateStackedMergeCommitsJob.perform_later(stack_id, priority:)
        stacked = true
      else
        CreateMergeCommitsJob.perform_later(pull_request, priority:)
        stacked = false
      end

      tags = [
        "from:#{GitHub.context[:from].presence || GitHub.context[:job].presence || "unknown"}",
        "catalog_service:#{GitHub.context[:catalog_service]}",
        "feature:create",
        "stacked:#{stacked}"
      ]

      if FeatureFlag.vexi.enabled?(:spokesd_spec_tagged_metrics, repository, default: false)
        tags << "nwo:#{repository.name_with_display_owner}"
      end

      GitHub.dogstats.increment("merge_commit.enqueued", tags:)
    end

    sig { params(pull_request: PullRequest).void }
    def self.enqueue_delete(pull_request:)
      DeleteMergeCommitsJob.perform_later(pull_request)

      repository = pull_request.repository
      tags = [
        "from:#{GitHub.context[:from].presence || GitHub.context[:job].presence || "unknown"}",
        "catalog_service:#{GitHub.context[:catalog_service]}",
        "feature:delete"
      ]

      if FeatureFlag.vexi.enabled?(:spokesd_spec_tagged_metrics, repository, default: false)
        tags << "nwo:#{T.must(repository).name_with_display_owner}"
      end

      GitHub.dogstats.increment("merge_commit.enqueued", tags:)
    end

    sig { params(target_sha: T.nilable(String), expected_sha: T.nilable(String)).returns(T::Boolean) }
    def self.up_to_date?(target_sha:, expected_sha:)
      return false if target_sha.nil? || target_sha.blank? || expected_sha.nil? || expected_sha.blank?
      target_sha == expected_sha
    end
  end
end
