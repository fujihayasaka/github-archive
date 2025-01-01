# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityOverviewAnalytics
  class FeatureStatus < ApplicationRecord::SecurityOverviewAnalytics
    include GitHub::SecurityCenter::LoggingHelper
    self.table_name = "soa_feature_statuses"

    belongs_to :repository_metadata,
      class_name: SecurityOverviewAnalytics::Repository.name,
      foreign_key: :repository_id,
      inverse_of: :feature_status_summary

    belongs_to :repository, class_name: "::Repository"

    sig { params(repository_id: Integer).void }
    def self.update_summary(repository_id:)
      GitHub.logger.with_named_tags("gh.repo.id": repository_id) do
        current_feature_statuses = log_timing(step: "fetch feature status revision") do
          FeatureStatusRevision
            .where(repository_id:)
            .where(next_revision_date_id: Date::FUTURE_DATE_ID)
            .first
        end

        current_dependabot_alerts = \
          if current_feature_statuses&.dependabot_alerts_enabled
            log_timing(step: "fetch dependabot alert counts") do
              DependabotAlertRevision
                .where(repository_id:)
                .where(next_revision_date_id: Date::FUTURE_DATE_ID)
                .where(alert_resolved: false)
                .group(:alert_severity)
                .count
                .transform_keys(&:downcase)
                .symbolize_keys
            end
          end

        current_code_scanning_alerts = \
          if current_feature_statuses&.code_scanning_enabled
            log_timing(step: "fetch code scanning alert counts") do
              CodeScanningAlertRevision
                .where(repository_id:)
                .where(next_revision_date_id: Date::FUTURE_DATE_ID)
                .where(alert_resolved: false)
                .group(:alert_severity)
                .count
                .transform_keys { |key| key&.downcase || "info" } # error/warning/note alerts are stored without severity
                .symbolize_keys
            end
          end

        current_secret_scanning_alerts = \
          if current_feature_statuses&.secret_scanning_enabled
            log_timing(step: "fetch secret scanning alert counts") do
              SecretScanningAlertRevision
                .where(repository_id:)
                .where(next_revision_date_id: Date::FUTURE_DATE_ID)
                .where(alert_resolved: false)
                .count
            end
          end

        update_payload = log_timing(step: "build payload") do
          {
            advanced_security_status: current_feature_statuses&.advanced_security_enabled ? :ENABLED : :NOT_ENABLED,
            # Dependabot
            dependabot_alerts_status: current_feature_statuses&.dependabot_alerts_enabled ? :ENABLED : :NOT_ENABLED,
            dependabot_alerts_total_count: current_dependabot_alerts&.values&.sum || 0,
            dependabot_alerts_critical_count: current_dependabot_alerts&.dig(:critical) || 0,
            dependabot_alerts_high_count: current_dependabot_alerts&.dig(:high) || 0,
            dependabot_alerts_medium_count: current_dependabot_alerts&.dig(:moderate) || 0,
            dependabot_alerts_low_count: current_dependabot_alerts&.dig(:low) || 0,
            # Code scanning
            code_scanning_alerts_status:  current_feature_statuses&.code_scanning_enabled ? :ENABLED : :NOT_ENABLED,
            code_scanning_alerts_total_count: current_code_scanning_alerts&.values&.sum || 0,
            code_scanning_alerts_critical_count: current_code_scanning_alerts&.dig(:critical) || 0,
            code_scanning_alerts_high_count: current_code_scanning_alerts&.dig(:high) || 0,
            code_scanning_alerts_medium_count: current_code_scanning_alerts&.dig(:medium) || 0,
            code_scanning_alerts_low_count: current_code_scanning_alerts&.dig(:low) || 0,
            code_scanning_alerts_info_count: current_code_scanning_alerts&.dig(:info) || 0,
            # Secret scanning
            secret_scanning_alerts_status:  current_feature_statuses&.secret_scanning_enabled ? :ENABLED : :NOT_ENABLED,
            secret_scanning_alerts_total_count: current_secret_scanning_alerts || 0,
            # Ancillary feature statuses
            dependabot_security_updates_status:  current_feature_statuses&.dependabot_security_updates_enabled ? :ENABLED : :NOT_ENABLED,
            dependabot_version_updates_status: current_feature_statuses&.dependabot_version_updates_enabled ? :ENABLED : :NOT_ENABLED,
            code_scanning_auto_codeql_status: \
              if current_feature_statuses&.code_scanning_auto_codeql_enabled
                :ENABLED
              elsif current_feature_statuses&.code_scanning_auto_codeql_eligible
                :ELIGIBLE
              else
                :NOT_ELIGIBLE
              end,
            code_scanning_pr_reviews_status:  current_feature_statuses&.code_scanning_pr_alerts_enabled ? :ENABLED : :NOT_ENABLED,
            secret_scanning_push_protection_status:  current_feature_statuses&.secret_scanning_push_protection_enabled ? :ENABLED : :NOT_ENABLED,
          }
        end

        summary = log_timing(step: "fetch existing feature status record") do
          FeatureStatus.find_by(repository_id:)
        end

        FeatureStatus.throttle_writes_with_retry do
          if summary.present?
            log_timing(step: "update existing feature status record") do
              summary.update!(**update_payload)
            end
          else
            now = Time.now
            log_timing(step: "upsert new feature status record") do
              # rubocop:disable GitHub/UpsertAll
              FeatureStatus.upsert_all(
                [{
                  repository_id:,
                  created_at: now,
                  updated_at: now,
                  **update_payload,
                }],
                update_only: [
                  :updated_at,
                  *update_payload.keys,
                ]
              )
            end
          end
        end
      end
    end

    sig { params(repository_ids: T::Array[Integer]).void }
    def self.delete_by_repository_ids(repository_ids)
      self.where(repository_id: repository_ids).in_batches do |batch|
        batch_size = batch.size
        self.throttle_writes_with_retry do
          batch.delete_all
          GitHub.dogstats.count("security_overview_analytics.feature_status.deleted", batch_size)
        end
      end
    end

    instrument_method \
      :update_summary,
      :delete_by_repository_ids
  end
end
