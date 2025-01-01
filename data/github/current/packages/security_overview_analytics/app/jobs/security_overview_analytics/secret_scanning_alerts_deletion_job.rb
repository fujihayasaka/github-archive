# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class SecretScanningAlertsDeletionJob < ApplicationJob
    extend T::Sig
    include GitHub::Memoizer

    queue_as :security_overview_analytics_secret_scanning_alert_revision_ingestion

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    RETRYABLE_ERRORS = T.let([
      ActiveRecord::RecordNotFound, # replication lag
      ActiveRecord::Deadlocked, # DB deadlock
      Freno::Error
    ], T::Array[T.class_of(StandardError)])
    # Workaround for https://sorbet.org/docs/error-reference#7019
    T.unsafe(self).retry_on *RETRYABLE_ERRORS, wait: :polynomially_longer

    use_replicas ApplicationRecord::SecurityOverviewAnalytics,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Configurations

    sig do
      params(
        repository_id: Integer,
        alert_numbers: T::Array[Integer],
      ).void
    end
    def perform(repository_id:, alert_numbers:)
      return unless should_perform?

      SecretScanningAlertRevision.delete_alerts(repository_id:, alert_numbers:)

      GitHub.logger.info(
        "Repository alerts deleted",
        "code.namespace": self.class.name,
        "code.function": __method__,
      )
    end

    protected

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.id": repository_id,
        "gh.security_overview_analytics.alert_numbers": alert_numbers,
        "gh.repo.owner.id": repository.owner&.id,
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({
        app: "github-security-center"
      })
    end

    private

    sig { returns(Integer) }
    memoize def repository_id
      arguments.dig(0, :repository_id)
    end

    sig { returns(::Repository) }
    memoize def repository
      ::Repositories::Public.get_active_or_deleted!(repository_id)
    end

    sig { returns(T::Array[Integer]) }
    memoize def alert_numbers
      arguments.dig(0, :alert_numbers)
    end

    sig { returns(T::Boolean) }
    def should_perform?
      if repository.deleted?
        GitHub.logger.info(
          "Alerts deletion skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.job.reason": "Repository soft-deleted.",
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.secret_scanning_alerts_deletion.skipped",
          tags: all_stats_tags + ["reason:repository_deleted"]
        )
        return false
      end

      unless repository.owner&.organization? || repository.owner&.is_enterprise_managed?
        GitHub.logger.info(
          "Alerts deletion skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.job.reason": "Not org or EMU owned repository.",
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.secret_scanning_alerts_deletion.skipped",
          tags: all_stats_tags + ["reason:not_org_or_emu_owned_repo"]
        )
        return false
      end

      owner = T.must(repository.owner)
      unless TenantValidationHelper.is_owner_in_scope?(owner)
        GitHub.logger.info(
          "Alerts deletion skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.job.reason": "Tenant not in scope.",
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.secret_scanning_alerts_deletion.skipped",
          tags: all_stats_tags + ["reason:tenant_not_in_scope"]
        )
        return false
      end

      true
    end
  end
end
