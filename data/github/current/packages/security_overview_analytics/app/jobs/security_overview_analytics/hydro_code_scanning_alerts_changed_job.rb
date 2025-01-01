# typed: strict
# frozen_string_literal: true

require "turboscan"

module SecurityOverviewAnalytics
  class HydroCodeScanningAlertsChangedJob < SecurityFeatureAlertsHydroMessageJob
    TurboscanInsightsAlert = ::Turboscan::Proto::InsightsAlert

    queue_as :hydro_security_overview_analytics_code_scanning_alerts_changed

    sig { void }
    def perform
      updated_alerts.each do |payload|
        next unless should_handle_alert_event?(payload)
        next unless valid_payload?(payload)
        alert = to_insights_alert(payload)
        CodeScanningAlertRevisionIngestionJob.perform_later(
          alert:,
          event_time:,
          deleted: false,
          source_event: "#{source_event}#upsert",
        )
      end

      deleted_alerts.each do |payload|
        next unless should_handle_alert_event?(payload)
        next unless valid_payload?(payload)
        alert = to_insights_alert(payload)
        # Use event timestamp for date_id of deleted alerts because original records are no longer available
        CodeScanningAlertRevisionIngestionJob.perform_later(
          alert:,
          event_time:,
          deleted: true,
          source_event: "#{source_event}#delete",
        )
      end
    end

    private

    sig { override.returns(String) }
    def feature_type
      Initialization::Type::CodeScanningAlert.serialize
    end

    sig { override.params(owner: ::User).returns(T::Boolean) }
    def should_handle_event_for_owner?(owner)
      TenantValidationHelper.should_handle_code_scanning_alert_events?(owner)
    end

    sig { params(hash: T::Hash[String, String]).returns(T::Boolean) }
    def valid_payload?(hash)
      InsightsBatchItem.props.stringify_keys.keys.each do |field|
        unless hash.has_key?(field)
          GitHub.dogstats.increment("security_overview_analytics.code_scanning_alert_revision_ingestion.skipped", tags: all_stats_tags + ["cause:missing_#{field}"])
          GitHub.logger.warn("Missing #{field} in InsightsEntityBatch payload")
          return false
        end
      end

      true
    end

    sig { params(hash: T::Hash[String, String]).returns(TurboscanInsightsAlert) }
    def to_insights_alert(hash)
      # InsightsEntityBatch uses a stringly-typed map to pass data; we must re-parse that to usable types.
      # https://github.com/github/turboscan/blob/fff5dd492274f4efb64cdbb53b28c97d6c2406f0/ts/hydro/publishers/insights_alert_handler.go#L92
      item = T.let(InsightsBatchItem.from_hash(hash), InsightsBatchItem)

      TurboscanInsightsAlert.new(
        id: item.id&.to_i,
        number: item.number&.to_i,
        repository_id: item.repository_id&.to_i,
        created_at: item.created_at&.to_time,
        updated_at: item.updated_at&.to_time,
        resolution: \
          if item.resolution&.to_i
            ::Turboscan::Proto::ResultResolution.lookup(item.resolution.to_i)
          end,
        rule_name: item.rule_name,
        rule_sarif_identifier: item.rule_sarif_identifier,
        tool_name: item.tool_name,
        severity: \
          if item.severity&.to_i
            ::Turboscan::Proto::SecuritySeverity.lookup(item.severity.to_i)
          end,
        closed_at: item.closed_at&.to_time,
        closed: item.closed == "true",
        present_on_default_ref: item.present_on_default_ref == "true",
      )
    end

    # This structure represents a single item in the InsightsEntityBatch event as published from turboscan.
    # All fields here are optional string, but this is used to validate expected payload, and provide
    # a level of safety for field names.
    class InsightsBatchItem < T::Struct
      const :id, T.nilable(String)
      const :number, T.nilable(String)
      const :repository_id, T.nilable(String)
      const :created_at, T.nilable(String)
      const :updated_at, T.nilable(String)
      const :resolution, T.nilable(String)
      const :rule_name, T.nilable(String)
      const :rule_sarif_identifier, T.nilable(String)
      const :tool_name, T.nilable(String)
      const :severity, T.nilable(String)
      const :closed_at, T.nilable(String)
      const :closed, T.nilable(String)
      const :present_on_default_ref, T.nilable(String)
      const :source_time, T.nilable(String)
    end
  end
end
