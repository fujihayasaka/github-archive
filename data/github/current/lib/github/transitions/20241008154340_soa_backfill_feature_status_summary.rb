# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "github/security_center/logging_helper"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class SoaBackfillFeatureStatusSummary < Base
      include GitHub::SecurityCenter::LoggingHelper

      class SoaRepository < ApplicationRecord::SecurityOverviewAnalytics
        self.table_name = "soa_repositories"

        # Map repository to id, as data table iterator operates on hardcoded `id` field name
        default_scope -> { from("(select *, repository_id as id from soa_repositories) soa_repositories") }

        # Still need alias as data table iterator validator uses unscoped query
        alias_attribute :id, :repository_id
      end

      iterate_over :database_table, params: {
        model_class: SoaRepository,
        columns: %i[owner_id],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        owner_ids = items.values.map { |v| v[:owner_id] }
        owners_by_id = ::User.where(id: owner_ids).index_by(&:id)

        items.each do |key, value|
          repository_id = T.cast(key, Integer)
          owner_id = T.cast(value[:owner_id], Integer)
          owner = owners_by_id[owner_id]

          unless owner.present?
            next log("Repository owner not found, skipping", repository_id:, owner_id:)
          end

          unless SecurityOverviewAnalytics::TenantValidationHelper.is_owner_in_scope?(owner)
            next log("Repository owner not in scope, skipping", repository_id:, owner_id:)
          end

          if dry_run?
            log "Dry run: would update feature status summary for repository: #{repository_id}"
          else
            update_summary(repository_id:)
            log "Updated feature status summary for repository: #{repository_id}"
          end
        end
      end

      sig { params(repository_id: Integer).void }
      def update_summary(repository_id:)
        GitHub.logger.with_named_tags("gh.repo.id": repository_id) do
          current_feature_statuses = log_timing(step: "fetch feature status revision") do
            SecurityOverviewAnalytics::FeatureStatusRevision
              .where(repository_id:)
              .where(next_revision_date_id: SecurityOverviewAnalytics::Date::FUTURE_DATE_ID)
              .first
          end

          current_dependabot_alerts = \
            if current_feature_statuses&.dependabot_alerts_enabled
              log_timing(step: "fetch dependabot alert counts") do
                SecurityOverviewAnalytics::DependabotAlertRevision
                  .where(repository_id:)
                  .where(next_revision_date_id: SecurityOverviewAnalytics::Date::FUTURE_DATE_ID)
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
                SecurityOverviewAnalytics::CodeScanningAlertRevision
                  .where(repository_id:)
                  .where(next_revision_date_id: SecurityOverviewAnalytics::Date::FUTURE_DATE_ID)
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
                SecurityOverviewAnalytics::SecretScanningAlertRevision
                  .where(repository_id:)
                  .where(next_revision_date_id: SecurityOverviewAnalytics::Date::FUTURE_DATE_ID)
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
                else
                  :NOT_ELIGIBLE
                end,
              code_scanning_pr_reviews_status:  current_feature_statuses&.code_scanning_pr_alerts_enabled ? :ENABLED : :NOT_ENABLED,
              secret_scanning_push_protection_status:  current_feature_statuses&.secret_scanning_push_protection_enabled ? :ENABLED : :NOT_ENABLED,
            }
          end

          summary = log_timing(step: "fetch existing feature status record") do
            SecurityOverviewAnalytics::FeatureStatus.find_by(repository_id:)
          end

          SecurityOverviewAnalytics::FeatureStatus.throttle_writes_with_retry do
            if summary.present?
              log_timing(step: "update existing feature status record") do
                summary.update!(**update_payload)
              end
            else
              now = Time.now
              log_timing(step: "upsert new feature status record") do
                # rubocop:disable GitHub/UpsertAll
                SecurityOverviewAnalytics::FeatureStatus.upsert_all(
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
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::SoaBackfillFeatureStatusSummary.new(args).run
end
