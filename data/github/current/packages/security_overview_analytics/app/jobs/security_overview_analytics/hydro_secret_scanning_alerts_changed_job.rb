# typed: strict
# frozen_string_literal: true

require "secret_scanning_proto"

module SecurityOverviewAnalytics
  class HydroSecretScanningAlertsChangedJob < SecurityFeatureAlertsHydroMessageJob
    SecretScanningAlert = ::GitHub::Proto::SecretScanning::Metrics::V1::Alert
    SecretScanningAlertResolution = ::GitHub::Proto::SecretScanning::Types::V1::TokenResolution
    SecretScanningTokenValidity = ::GitHub::Proto::SecretScanning::Types::V1::TokenValidity

    queue_as :hydro_security_overview_analytics_secret_scanning_alerts_changed

    sig { void }
    def perform
      updated_alerts.each do |payload|
        next unless should_handle_alert_event?(payload)
        next unless valid_update_payload?(payload)
        alert = to_alert(payload)
        date_id = Date.id_from_time(alert.updated_at&.to_time)
        SecretScanningAlertRevisionIngestionJob.perform_later(
          alert:,
          event_time:,
          source_event: "#{source_event}#upsert",
        )
      end

      deleted_alerts.each do |payload|
        next unless should_handle_alert_event?(payload)
        next unless valid_delete_payload?(payload)
        alert = to_alert(payload)
        SecretScanningAlertsDeletionJob.perform_later(repository_id: alert.repository_id, alert_numbers: [alert.number])
      end
    end

    private

    sig { override.returns(String) }
    def feature_type
      Initialization::Type::SecretScanningAlert.serialize
    end

    sig { override.params(owner: ::User).returns(T::Boolean) }
    def should_handle_event_for_owner?(owner)
      TenantValidationHelper.should_handle_secret_scanning_alert_events?(owner)
    end

    sig { params(alert_payload: T::Hash[String, String]).returns(T::Boolean) }
    def valid_update_payload?(alert_payload)
      %w[repository_id number created_at updated_at token_type slug resolved].each do |field|
        next if alert_payload[field].present?
        GitHub.dogstats.increment("security_overview_analytics.secret_scanning_alert_revision_ingestion.skipped", tags: all_stats_tags + ["cause:missing_#{field}"])
        GitHub.logger.warn(
          "Missing #{field} in InsightsEntityBatch payload",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.alert": alert_payload,
        )
        return false
      end

      if alert_payload["resolved"] == "true" && alert_payload["resolution"].nil?
        GitHub.dogstats.increment("security_overview_analytics.secret_scanning_alert_revision_ingestion.skipped", tags: all_stats_tags + ["cause:missing_resolution"])
        GitHub.logger.warn(
          "Missing resolution in InsightsEntityBatch payload",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.alert": alert_payload
        )
        return false
      end

      if !alert_payload["token_type"]&.start_with?("cp_") && alert_payload["token_type_provider"].nil?
        GitHub.logger.warn(
          "Missing token_type_provider in InsightsEntityBatch payload for non-custom-pattern alert type",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.alert": alert_payload
        )
      end

      true
    end

    sig { params(alert_payload: T::Hash[String, String]).returns(T::Boolean) }
    def valid_delete_payload?(alert_payload)
      %w[repository_id number].each do |field|
        next if alert_payload[field].present?
        GitHub.dogstats.increment("security_overview_analytics.secret_scanning_alert_revision_ingestion.skipped", tags: all_stats_tags + ["cause:missing_#{field}"])
        GitHub.logger.warn(
          "Missing #{field} in InsightsEntityBatch payload",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.alert": alert_payload,
        )
        return false
      end

      true
    end

    sig { params(alert_payload: T::Hash[String, String]).returns(SecretScanningAlert) }
    def to_alert(alert_payload)
      SecretScanningAlert.new(
        repository_id: alert_payload["repository_id"].to_i,
        number: alert_payload["number"].to_i,
        created_at: alert_payload["created_at"]&.to_time,
        updated_at: alert_payload["updated_at"]&.to_time,
        token_type: alert_payload["token_type"],
        token_type_provider: alert_payload["token_type_provider"],
        slug: alert_payload["slug"],
        resolved: alert_payload["resolved"] == "true",
        resolution: \
          if alert_payload["resolution"]&.to_i
            SecretScanningAlertResolution.lookup(alert_payload["resolution"].to_i)
          end,
        resolved_at: alert_payload["resolved_at"]&.to_time,
        has_valid_locations: alert_payload["has_valid_locations"] == "true",
        validity: \
          if alert_payload["validity"]&.to_i
            SecretScanningTokenValidity.lookup(alert_payload["validity"].to_i)
          end,
        bypassed: alert_payload["bypassed"] == "true"
      )
    end
  end
end
