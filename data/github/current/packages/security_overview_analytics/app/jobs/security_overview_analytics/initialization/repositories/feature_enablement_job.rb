# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class Initialization
    module Repositories
      class FeatureEnablementJob < BaseJob
        queue_as :security_overview_analytics_repository_initialization

        RETRYABLE_EXCEPTIONS = T.let([
          CodeScanning::AutoCodeqlError,
          Faraday::TimeoutError,
        ], T::Array[T::Class[T.anything]])
        retry_on *T.unsafe(RETRYABLE_EXCEPTIONS), wait: :polynomially_longer

        # Don't enqueue if feature revisions already exist for the repository
        around_enqueue do |_, block|
          if SecurityOverviewAnalytics::FeatureStatusRevision.where(repository_id: repository_id).exists?
            GitHub.logger.info("FeatureStatusRevisions already exist for repository")
            GitHub.dogstats.increment(
              "security_overview_analytics.initialization.feature_enablement.skipped",
              tags: all_stats_tags + ["reason:revisions_already_exist"]
            )
            clear_lock
            next
          end

          block.call
        end

        sig { override.params(repository_id: Integer).void }
        def perform(repository_id:)
          upsert_payload = repository_payload
          SecurityOverviewAnalytics::FeatureStatusRevision.throttle_writes_with_retry(max_retry_count: 5, err_msg: "Upserting SecurityOverviewAnalytics::FeatureStatusRevision in #{self.class}.") do
            SecurityOverviewAnalytics::FeatureStatusRevision.upsert_feature_status(
              date_id:,
              payload: upsert_payload,
              repository_id:
            )
          end
        end

        sig { returns(FeatureStatusRevision::UpdatePayload) }
        def repository_payload
          code_scanning_auto_codeql_enabled, code_scanning_auto_codeql_eligible = \
            FeatureStatusRevision.code_scanning_auto_codeql_status(repository:)&.values_at(:enabled, :eligible)

          FeatureStatusRevision::UpdatePayload.new(
            advanced_security_enabled: repository.security_feature_configured?(:ADVANCED_SECURITY),
            code_scanning_enabled: repository.security_feature_configured?(:CODE_SCANNING),
            code_scanning_pr_alerts_enabled: repository.security_feature_configured?(:CODE_SCANNING_PR_REVIEWS),
            code_scanning_auto_codeql_enabled:,
            code_scanning_auto_codeql_eligible:,
            dependabot_alerts_enabled: repository.security_feature_configured?(:DEPENDABOT_ALERTS),
            dependabot_security_updates_enabled: repository.security_feature_configured?(:DEPENDABOT_SECURITY_UPDATES),
            secret_scanning_enabled: repository.security_feature_configured?(:SECRET_SCANNING),
            secret_scanning_push_protection_enabled: repository.security_feature_configured?(:SECRET_SCANNING_PUSH_PROTECTION)
          )
        end
      end
    end
  end
end
