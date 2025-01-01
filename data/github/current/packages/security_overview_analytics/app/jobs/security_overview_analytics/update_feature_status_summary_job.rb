# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class UpdateFeatureStatusSummaryJob < ApplicationJob

    queue_as :security_overview_analytics_update_feature_status_summary

    locked_by timeout: DEFAULT_LOCK_TIMEOUT, key: DEFAULT_LOCK_PROC

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    # STOP - Please do not add more cluster dependencies here.
    # The `FeatureStatus` summary/rollup should _only_ be built from the `*Revision` data we already have.
    use_replicas \
      ApplicationRecord::SecurityOverviewAnalytics,
      allow_replication_lag: []

    sig { params(repository_id: Integer).void }
    def self.enqueue(repository_id:)
      # Use `enqueue_once_per_interval` to avoid spammy recalculations in periods of high event traffic.
      # We'll update at most once every 30s per repository.
      UpdateFeatureStatusSummaryJob.enqueue_once_per_interval(
        kwargs: {
          repository_id:,
        },
        interval: 30, # seconds
      )
    end

    sig { params(repository_id: Integer).void }
    def perform(repository_id:)
      FeatureStatus.update_summary(repository_id:)
    end

    protected

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      kwargs = arguments.first || {}
      super.merge({
        "gh.repo.id": kwargs.dig(:repository_id),
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({
        app: "github-security-center"
      })
    end
  end
end
