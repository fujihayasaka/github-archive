# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class CodeScanningPullRequestAlert < ApplicationRecord::SecurityOverviewAnalytics
    extend T::Sig

    self.table_name = "soa_code_scanning_pull_request_alerts"

    belongs_to :repository_metadata,
      class_name: SecurityOverviewAnalytics::Repository.name,
      foreign_key: :repository_id,
      inverse_of: :code_scanning_pull_request_alerts

    belongs_to :repository, class_name: "::Repository"

    SecuritySeverity = ::Turboscan::Proto::SecuritySeverity
    Resolution = ::Turboscan::Proto::ResultResolution

    class UpdatePayload < T::Struct
      extend T::Sig

      AnyTime = T.type_alias { T.any(ActiveSupport::TimeWithZone, Time) }

      const :repository_id, Integer
      const :alert_number, Integer
      const :pull_request_id, Integer
      const :analysis_id, Integer
      const :ref, String
      const :tool, String
      const :rule_sarif_identifier, String
      const :alert_updated_at, AnyTime
      const :alert_created_at, AnyTime
      const :alert_resolved_at, T.nilable(AnyTime)
      const :alert_severity, T.nilable(String)
      const :alert_resolved, T::Boolean
      const :alert_resolution, T.nilable(Integer)
      const :has_dfa, T.nilable(T::Boolean)
      const :has_dfa_comments, T.nilable(T::Boolean)
      const :has_autofix, T.nilable(T::Boolean)
      const :autofix_accepted, T.nilable(T::Boolean)

      sig { returns(T::Hash[String, T.untyped]) }
      def serialize
        super.tap do |h|
          h["alert_created_at"] = alert_created_at.iso8601(3).to_time.utc
          h["alert_updated_at"] = alert_updated_at.iso8601(3).to_time.utc
          h["alert_resolved_at"] = alert_resolved_at&.iso8601(3)&.to_time&.utc
          h["date_id"] = Date.id_from_time(alert_created_at)
        end
      end

      sig do
        params(
          pull_request: ::PullRequest,
          alert: ::SecurityProduct::PullRequestAlert,
          source_event: String,
        ).returns(UpdatePayload)
      end
      def self.from_pull_request_alert(pull_request:, alert:, source_event:)
        severity = if alert.severity.is_a?(Symbol) && alert.severity != SecuritySeverity.lookup(SecuritySeverity::NO_SECURITY_SEVERITY)
          alert.severity.to_s
        elsif alert.severity.is_a?(Integer) && alert.severity != SecuritySeverity::NO_SECURITY_SEVERITY
          SecuritySeverity.lookup(T.cast(alert.severity, Integer))&.to_s
        else
          nil
        end

        resolution = if alert.resolution.is_a?(Symbol) && alert.resolution != Resolution.lookup(Resolution::NO_RESOLUTION)
          Resolution.resolve(T.cast(alert.resolution, Symbol))&.to_i
        elsif alert.resolution.is_a?(Integer) && alert.resolution != Resolution::NO_RESOLUTION
          T.cast(alert.resolution, Integer)
        else
          nil
        end

        # Per Turboscan API
        # - "fixed == true" means fixed
        # - "resolution != :NO_RESOLUTION" means dismissed.
        # Per SOA, we consolidate everything into:
        # - "resolved == true && resolution.nil?" means alert was fixed
        # - "resolved == true && resolution.present?" means alert was dismissed
        resolved = alert.fixed || resolution.present?

        update_payload = UpdatePayload.new(
          repository_id: pull_request.repository_id,
          alert_number: alert.alert_number,
          pull_request_id: T.must(pull_request.id),
          analysis_id: alert.analysis_id,
          ref: pull_request.head_ref_name,
          tool: alert.tool,
          rule_sarif_identifier: alert.rule_sarif_identifier,
          alert_created_at: alert.created_at,
          alert_updated_at: alert.updated_at,
          alert_resolved_at: alert.fixed ? alert.fixed_at : alert.resolved_at,
          alert_severity: severity,
          alert_resolved: resolved,
          alert_resolution: resolution,
          has_dfa: alert.has_dfa,
          has_dfa_comments: alert.has_dfa_comments,
          has_autofix: alert.has_autofix,
          autofix_accepted: alert.autofix_accepted,
        )

        serialized_payload = update_payload.serialize
        alert_resolved_at = serialized_payload["alert_resolved_at"]
        pull_request_merged_at = pull_request.merged_at&.iso8601(3)&.to_time&.utc
        if pull_request_merged_at.present? && alert_resolved_at.present? && pull_request_merged_at < alert_resolved_at
          GitHub.logger.info(
            "Unexpected alert resolved_at.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_overview_analytics.pull_request_alert.update_payload": serialized_payload.inspect,
          )
          GitHub.dogstats.increment(
            "security_overview_analytics.code_scanning_pull_request_alert.unexpected_resolved_at",
            tags: ["source_event:#{source_event}"]
          )
        end

        update_payload
      end
    end

    sig do
      params(
        input_payload: T::Hash[String, T.untyped],
        existing_alert: T::Hash[String, T.untyped]
      ).void
    end
    def self.validate_and_report_unexpected_state_changes(input_payload, existing_alert)
      state_deviations = T.let([], T::Array[Symbol])
      state_deviations << :alert_resolved_at if input_payload["alert_resolved_at"] != existing_alert["alert_resolved_at"]&.iso8601(3)&.to_time&.utc
      state_deviations << :alert_resolved if input_payload["alert_resolved"] != existing_alert["alert_resolved"]
      state_deviations << :alert_resolution if input_payload["alert_resolution"] != existing_alert["alert_resolution"]

      return unless state_deviations.any?

      GitHub.logger.info(
        "Unexpected alert state.",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_overview_analytics.pull_request_alert.state_deviations": state_deviations.inspect,
        "gh.security_overview_analytics.pull_request_alert.input_payload": input_payload.inspect,
        "gh.security_overview_analytics.pull_request_alert.existing_alert": existing_alert.inspect,
      )
      GitHub.dogstats.increment(
        "security_overview_analytics.code_scanning_pull_request_alert.unexpected_state",
        tags: state_deviations.map { |d| "deviation:#{d}" }
      )
    end

    sig do
      params(
        payload: UpdatePayload,
        update_except: T::Array[String],
        force_rewrite: T::Boolean,
        dry_run: T::Boolean
      ).void
    end
    def self.upsert(payload, update_except: [], force_rewrite: false, dry_run: false)
      retry_count ||= 0

      serialized_payload = payload.serialize
      serialized_alert = T.let(nil, T.nilable(T::Hash[String, T.untyped]))

      CodeScanningPullRequestAlert.transaction do
        existing_alert = T.let(CodeScanningPullRequestAlert.find_by(
          repository_id: payload.repository_id,
          pull_request_id: payload.pull_request_id,
          alert_number: payload.alert_number
        )&.lock!, T.nilable(CodeScanningPullRequestAlert))

        if existing_alert.nil?
          CodeScanningPullRequestAlert.create!(**serialized_payload) unless dry_run
        else
          serialized_alert = existing_alert.attributes
          existing_alert_updated_at = existing_alert.alert_updated_at.iso8601(3).to_time.utc
          if existing_alert_updated_at < serialized_payload["alert_updated_at"] ||
            (force_rewrite && existing_alert_updated_at == serialized_payload["alert_updated_at"])

            update_payload = T.unsafe(serialized_payload).except(*update_except)

            existing_alert.update!(**update_payload) unless dry_run
          end
        end
      end

      # Validates for unexpected alert state.
      # Xref: https://github.com/github/security-center/issues/5830#issuecomment-2286912275
      if serialized_alert.present?
        validate_and_report_unexpected_state_changes(serialized_payload, serialized_alert)
      end
    rescue ActiveRecord::RecordNotUnique => e
      # This is possible due to racing condition where two workloads try to insert with the same unique key
      if retry_count&.zero?
        GitHub.logger.info(
          "Record already exists. Retry to attempt an update.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.payload": payload.serialize.inspect,
          "gh.security_overview_analytics.force_rewrite": force_rewrite,
        )
        retry_count += 1
        retry
      end

      raise e
    end

    sig { params(repository_ids: T::Array[Integer]).void }
    def self.delete_by_repository_ids(repository_ids)
      self.where(repository_id: repository_ids).in_batches do |batch|
        batch_size = batch.size
        self.throttle_writes_with_retry do
          batch.delete_all
          GitHub.dogstats.count("security_overview_analytics.code_scanning_pull_request_alerts.deleted", batch_size)
        end
      end
    end

    sig { params(payload: UpdatePayload).returns(T::Array[Symbol]) }
    def fields_with_deviation(payload)
      output = T.let([], T::Array[Symbol])

      output << :analysis_id if analysis_id != payload.analysis_id
      output << :alert_created_at if alert_created_at.iso8601(3).to_time.utc != payload.alert_created_at.iso8601(3).to_time.utc
      output << :alert_updated_at if alert_updated_at.iso8601(3).to_time.utc != payload.alert_updated_at.iso8601(3).to_time.utc
      output << :alert_resolved_at if alert_resolved_at&.iso8601(3)&.to_time&.utc != payload.alert_resolved_at&.iso8601(3)&.to_time&.utc
      output << :alert_resolved if alert_resolved != payload.alert_resolved
      output << :alert_resolution if alert_resolution != payload.alert_resolution
      output << :alert_severity if alert_severity != payload.alert_severity
      output << :ref if ref != payload.ref
      output << :tool if tool != payload.tool
      output << :rule_sarif_identifier if rule_sarif_identifier != payload.rule_sarif_identifier
      output << :has_dfa if has_dfa != payload.has_dfa
      output << :has_dfa_comments if has_dfa_comments != payload.has_dfa_comments
      output << :has_autofix if has_autofix != payload.has_autofix
      output << :autofix_accepted if autofix_accepted != payload.autofix_accepted

      output
    end
  end
end
