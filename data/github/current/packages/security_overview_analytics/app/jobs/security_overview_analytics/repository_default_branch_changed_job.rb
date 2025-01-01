# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class RepositoryDefaultBranchChangedJob < ApplicationJob
    include GitHub::Memoizer

    queue_as :security_overview_analytics_repository_default_branch_changed

    locked_by timeout: DEFAULT_LOCK_TIMEOUT, key: DEFAULT_LOCK_PROC

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    use_replicas \
      ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::SecurityOverviewAnalytics,
      ApplicationRecord::Spokes,
      allow_replication_lag: []

    around_perform do |_, block|
      next if repository.deleted?
      next unless TenantValidationHelper.should_handle_repository_lifecycle_events?(repository.owner_id)

      block.call
    end

    sig { params(repository_id: Integer).void }
    def perform(repository_id:)
      # purge all existing code scanning alert revisions
      CodeScanningAlertRevision.where(repository_id:).in_batches do |rev_batch|
        CodeScanningAlertRevision.throttle_writes_with_retry do
          rev_batch.delete_all
          GitHub.dogstats.count("security_overview_analytics.reset.code_scanning_alert_revisions.deleted", rev_batch.size)
        end
      end

      # queue for re-backfill
      # wait an arbitrary amount of time for code scanning to be notified of the default branch change
      Initialization::Repositories::CodeScanningAlertsJob.
        set(wait: 5.minutes).
        perform_later(repository_id:)
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

    sig { returns(::Repository) }
    memoize def repository
      repository_id = arguments.first&.dig(:repository_id)
      ::Repositories::Public.get_active_or_deleted!(repository_id)
    end
  end
end
