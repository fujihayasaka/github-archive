# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Reconciliation
    class PostReconciliationRepoDeviationCountsJob < ApplicationJob
      extend T::Sig

      queue_as :security_overview_analytics_tenant_reconciliation

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      NO_DEVIATIONS = T.let([0, 0], [Integer, Integer])

      sig { params(repository_id: Integer, owner_id: Integer, feature: String).void }
      def self.perform_with_delay(repository_id:, owner_id:, feature:)
        self.set(wait: 1.hour).perform_later(repository_id:, owner_id:, feature:)
      end

      sig { params(repository_id: Integer, owner_id: Integer, feature: String).void }
      def perform(repository_id:, owner_id:, feature:)
        open_difference, closed_difference = case feature
        when "dependabot"
          get_soa_and_dbot_alert_count_differences
        when "secret-scanning"
          get_soa_and_tss_alert_count_differences
        when "code-scanning"
          get_soa_and_ts_alert_count_differences
        else
          NO_DEVIATIONS
        end

        unless open_difference.zero? && closed_difference.zero?
          GitHub.logger.info(
            "Deviations found after reconciliation completed.",
            "gh.security_overview_analytics.job.feature": feature,
            "gh.security_overview_analytics.job.open_deviations_count": open_difference,
            "gh.security_overview_analytics.job.closed_deviations_count": closed_difference,
            "gh.repo.id": repository_id,
            "gh.owner.id": owner_id,
          )
          GitHub.dogstats.increment(
            "security_overview_analytics.reconciliation.post_reconciliation_deviations_found",
            tags: ["feature:#{feature}"]
          )
        end
      end

      private

      sig { returns(Integer) }
      def repository_id
        arguments.dig(0, :repository_id)
      end

      sig { returns(Integer) }
      def owner_id
        arguments.dig(0, :owner_id)
      end

      sig { returns(String) }
      def feature
        arguments.dig(0, :feature)
      end

      sig { returns(::Repository) }
      def repository
        ::Repositories::Public.get_active_or_deleted!(repository_id)
      end

      sig { returns([Integer, Integer]) }
      def get_soa_and_tss_alert_count_differences
        return NO_DEVIATIONS unless repository.security_feature_configured?(:SECRET_SCANNING)

        # Get our SOA counts
        soa_alert_counts = SecretScanningAlertRevision
          .where(repository_id:, next_revision_date_id: Date::FUTURE_DATE_ID)
          .group(:alert_resolved)
          .count
        soa_open_count = soa_alert_counts[false] || 0
        soa_closed_count = soa_alert_counts[true] || 0

        # Get the Token Scanning Service counts
        request = GitHub::Proto::SecretScanning::Api::V2::GetTokensRequest.new({
          repo_selector: ::GitHub::Proto::SecretScanning::Api::V2::RepoSelector.new(repository_id: repository_id),
          token_state: 1,
          low_confidence: false,
          sort_order: Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_SORT_SERVICE_ENUM,
          page: 1,
          limit: 1
        })
        response = GitHub::TokenScanning::Service::Client.new(nil).get_tokens(request.to_h)
        response_data = response.try(:data)
        return NO_DEVIATIONS if response.nil? || response_data.nil? || response.error.present?

        tss_open_count = response_data.try(:unresolved_count)
        tss_closed_count = response_data.try(:resolved_count)
        return NO_DEVIATIONS if tss_open_count.nil? || tss_closed_count.nil?

        [tss_open_count - soa_open_count, tss_closed_count - soa_closed_count]
      end

      sig { returns([Integer, Integer]) }
      def get_soa_and_dbot_alert_count_differences
        return NO_DEVIATIONS unless repository.security_feature_configured?(:DEPENDABOT_ALERTS)

        # Get our SOA counts
        soa_alert_counts = DependabotAlertRevision
          .where(repository_id:, next_revision_date_id: Date::FUTURE_DATE_ID)
          .group(:alert_resolved)
          .count

        soa_open_count = soa_alert_counts[false] || 0
        soa_closed_count = soa_alert_counts[true] || 0

        # Get the dependabot counts
        dbot_alerts = RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(repository: repository)

        [dbot_alerts.open_count - soa_open_count, dbot_alerts.closed_count - soa_closed_count]
      end

      sig { returns([Integer, Integer]) }
      def get_soa_and_ts_alert_count_differences
        return NO_DEVIATIONS unless repository.security_feature_configured?(:CODE_SCANNING)

        # Get our SOA counts
        soa_alert_counts = CodeScanningAlertRevision
          .where(repository_id:, next_revision_date_id: Date::FUTURE_DATE_ID)
          .group(:alert_resolved)
          .count
        soa_open_count = soa_alert_counts[false] || 0
        soa_closed_count = soa_alert_counts[true] || 0

        # Get the Turboscan counts
        request_hash = {
          limit: 1,
          numeric_page: 1,
          repository_ids: [repository_id],
          owner_ids: [owner_id],
        }
        response = GitHub::Turboscan.alerts_by_repo(Turboscan::Proto::AlertsByRepoRequest.new(request_hash).to_h)
        return NO_DEVIATIONS if response.nil? || response.error.present?

        ts_open_count = response.try(:data).try(:open_count)
        ts_closed_count = response.try(:data).try(:resolved_count)
        return NO_DEVIATIONS if ts_open_count.nil? || ts_closed_count.nil?

        [ts_open_count - soa_open_count, ts_closed_count - soa_closed_count]
      end
    end
  end
end
