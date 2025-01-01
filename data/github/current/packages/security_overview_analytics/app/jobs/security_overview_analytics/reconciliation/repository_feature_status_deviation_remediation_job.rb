# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Reconciliation
    class RepositoryFeatureStatusDeviationRemediationJob < ApplicationJob

      queue_as :security_overview_analytics_repository_feature_status_deviation_remediation

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      RETRYABLE_EXCEPTIONS = T.let([
        ActiveRecord::Deadlocked,
        CodeScanning::AutoCodeqlError,
        Faraday::TimeoutError,
      ], T::Array[T::Class[T.anything]])
      retry_on *T.unsafe(RETRYABLE_EXCEPTIONS), wait: :polynomially_longer

      use_replicas \
        ApplicationRecord::Configurations,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Repositories,
        ApplicationRecord::SecurityOverviewAnalytics,
        allow_replication_lag: [
          ApplicationRecord::Collab,
          ApplicationRecord::Spokes,
        ]

      locked_by timeout: 15.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

      sig { params(session_id: String, repository_id: Integer).void }
      def perform(session_id:, repository_id:)
        repository = ::Repositories::Public.get_active_or_deleted(repository_id)
        remediation = :no_op

        if should_remediate?(repository:)
          date_id = Date.id_from_time(Time.current)

          code_scanning_auto_codeql_enabled, code_scanning_auto_codeql_eligible = \
            FeatureStatusRevision.code_scanning_auto_codeql_status(repository:)&.values_at(:enabled, :eligible)

          payload = FeatureStatusRevision::UpdatePayload.new(
            advanced_security_enabled: repository&.security_feature_configured?(:ADVANCED_SECURITY),
            code_scanning_enabled: repository&.security_feature_configured?(:CODE_SCANNING),
            code_scanning_pr_alerts_enabled: repository&.security_feature_configured?(:CODE_SCANNING_PR_REVIEWS),
            code_scanning_auto_codeql_enabled:,
            code_scanning_auto_codeql_eligible:,
            dependabot_alerts_enabled: repository&.security_feature_configured?(:DEPENDABOT_ALERTS),
            dependabot_security_updates_enabled: repository&.security_feature_configured?(:DEPENDABOT_SECURITY_UPDATES),
            secret_scanning_enabled: repository&.security_feature_configured?(:SECRET_SCANNING),
            secret_scanning_push_protection_enabled: repository&.security_feature_configured?(:SECRET_SCANNING_PUSH_PROTECTION)
          )
          FeatureStatusRevision.throttle do
            with_write do
              FeatureStatusRevision.upsert_feature_status(repository_id:, date_id:, payload:)
            end
          end
          remediation = :feature_status_upserted
        end

        GitHub.logger.info(
          "Deviation remediation completed.",
          "code.namespace": self.class.name,
          "code.function": __method__
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.repository_feature_status_deviation_remediation.completed",
          tags: all_stats_tags + ["remediation:#{remediation}"]
        )
      end

      protected

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def logging_context
        super.merge({
          "gh.repo.id": arguments.dig(0, :repository_id),
          "gh.security_overview_analytics.job.session_id": arguments.dig(0, :session_id)
        })
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def failbot_context
        super.merge({
          app: "github-security-center"
        })
      end

      private

      sig { params(repository: T.nilable(::Repository)).returns(T::Boolean) }
      def should_remediate?(repository:)
        return false if repository.nil?
        return false if repository.deleted?

        owner = repository.owner
        return false if owner.nil?

        return false unless TenantValidationHelper.is_owner_in_scope?(owner)
        Initialization.for(owner).initialized?(type: Initialization::Type::FeatureEnablement)
      end
    end
  end
end
