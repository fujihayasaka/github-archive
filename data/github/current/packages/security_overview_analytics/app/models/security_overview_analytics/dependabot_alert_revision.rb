# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/security_alerts/v1/repository_vulnerability_alert_lifecycle_event_pb"

module SecurityOverviewAnalytics
  class DependabotAlertRevision < ApplicationRecord::SecurityOverviewAnalytics
    include RevisionCompressor

    self.table_name = "soa_dependabot_alert_revisions"

    after_commit :update_feature_status_summary

    sig { void }
    def update_feature_status_summary
      return unless next_revision_date_id == Date::FUTURE_DATE_ID
      UpdateFeatureStatusSummaryJob.enqueue(repository_id:)
    end

    Event = ::Hydro::Schemas::Github::SecurityAlerts::V1::RepositoryVulnerabilityAlertLifecycleEvent
    DependabotResolutions = Event::LastStateChangeReason

    QUALIFIER_ECOSYSTEM = "dependabot.ecosystem"
    QUALIFIER_PACKAGE = "dependabot.package"
    QUALIFIER_SCOPE = "dependabot.scope"
    QUALIFIER_ADVISORY = "dependabot.advisory"

    RESOLUTIONS_MAPPING = T.let({
      fixed_or_revoked: [
        DependabotResolutions::DEPENDENCY_CHANGED,
        DependabotResolutions::MANIFEST_DELETED,
        DependabotResolutions::MANIFEST_SUPERSEDED
      ],
      auto_dismissed: [
        DependabotResolutions::RULE_CREATED,
        DependabotResolutions::RULE_ENABLED,
        DependabotResolutions::RULE_UPDATED,
        DependabotResolutions::ALERT_CREATED,
        DependabotResolutions::ALERT_UPDATED,
        DependabotResolutions::PREVIOUS_RULE_DELETED,
        DependabotResolutions::PREVIOUS_RULE_DISABLED,
        DependabotResolutions::PREVIOUS_RULE_UPDATED
      ],
      false_positive: [
        DependabotResolutions::INACCURATE
      ],
      risk_accepted: [
        DependabotResolutions::FIX_STARTED,
        DependabotResolutions::NO_BANDWIDTH,
        DependabotResolutions::TOLERABLE_RISK,
        DependabotResolutions::NOT_USED
      ]
    }.with_indifferent_access.freeze, T::Hash[T.any(String, Symbol), T::Array[Integer]])


    sig { returns(String) }
    def self.feature_type
      "dependabot_alerts"
    end

    sig { returns(String) }
    def feature_type
      self.class.feature_type
    end

    sig { params(filters: T::Array[Symbol]).returns(T::Array[Integer]) }
    def self.to_closure_reasons(filters)
      closure_reasons = []
      filters.each do |filter|
        closure_reasons << RESOLUTIONS_MAPPING[filter]
      end

      closure_reasons.flatten
    end

    sig { params(filters: T::Array[String]).returns(T::Array[String]) }
    def self.to_valid_severities(filters)
      # We store "medium" as "moderate" in Dbot revisions
      filters.map { |f| f == "medium" ? "moderate" : f }
    end

    belongs_to :date,
      class_name: SecurityOverviewAnalytics::Date.name,
      inverse_of: :dependabot_alert_revisions
    belongs_to :next_revision_date,
      class_name: SecurityOverviewAnalytics::Date.name,
      inverse_of: :last_dependabot_alert_revisions
    belongs_to :repository_metadata,
      class_name: SecurityOverviewAnalytics::Repository.name,
      foreign_key: :repository_id,
      inverse_of: :dependabot_alert_revisions
    belongs_to :repository, class_name: "::Repository"

    sig { params(alert: RepositoryVulnerabilityAlert).returns(T::Array[Symbol]) }
    def fields_with_deviation(alert:)
      return [:repo_not_found] if repository.nil?
      return [:repo_deleted] if repository&.deleted?

      output = T.let([], T::Array[Symbol])

      output << :alert_resolved if alert_resolved != !alert.open?
      output << :alert_severity if alert_severity != alert.severity&.upcase
      output << :ghsa_id if ghsa_id != alert.vulnerability&.ghsa_id
      output << :package_name if package_name != alert.package_name
      output << :ecosystem if ecosystem != alert.ecosystem
      output << :dependency_scope if dependency_scope != alert.dependency_scope&.upcase

      # last_state_change_reason is stored as a String in RVA and as Integer in SOA, so we need to do some conversion
      output << :alert_resolution if resolution_reason_deviated?(alert.last_state_change_reason, alert_resolution)

      output
    end

    class UpdatePayload < T::Struct

      AnyTime = T.type_alias { T.any(ActiveSupport::TimeWithZone, Time) }

      const :alert_created_at, AnyTime
      const :alert_resolved, T::Boolean
      const :alert_resolved_at, T.nilable(AnyTime)
      const :alert_resolution, T.nilable(Integer)
      const :alert_severity, T.nilable(Symbol)
      const :alert_updated_at, AnyTime
      const :ghsa_id, String
      const :dependency_scope, Symbol
      const :ecosystem, String
      const :package_name, String

      sig { returns(T::Hash[String, T.untyped]) }
      def serialize
        super.tap do |h|
          # 'serialize' omits nil values from the hash output,
          # so we need to fill them back in.
          h["alert_resolved_at"] = nil if self.alert_resolved_at.nil?
          h["alert_resolution"] = nil if self.alert_resolution.nil?
        end
      end

      sig { params(other: UpdatePayload).returns(T::Boolean) }
      def ==(other)
        serialize == other.serialize
      end
    end

    sig do
      params(
        update_payload: UpdatePayload,
        repository_id: Integer,
        alert_number: Integer,
        force_rewrite: T::Boolean,
      ).void
    end
    def self.upsert_revision(update_payload, repository_id:, alert_number:, force_rewrite: false)
      RevisionUpserter.new(self).upsert(update_payload, repository_id:, alert_number:, force_rewrite:)
    end

    sig { params(event: Event).returns(UpdatePayload) }
    def self.create_update_payload(event)
      raise "Missing created_at in RepositoryVulnerabilityAlertLifecycleEvent payload" if event.created_at.nil?
      raise "Missing updated_at in RepositoryVulnerabilityAlertLifecycleEvent payload" if event.updated_at.nil?

      alert_severity =
        if event.severity == Event::Severity.lookup(Event::Severity::SEVERITY_UNKNOWN)
          nil
        else
          event.severity
        end
      raise "Unknown RepositoryVulnerabilityAlertLifecycleEvent::Severity enum value: #{alert_severity}" if alert_severity.is_a?(Integer)

      dependency_scope = event.dependency_scope
      raise "Unknown RepositoryVulnerabilityAlertLifecycleEvent::DependencyScope enum value: #{dependency_scope}" if dependency_scope.is_a?(Integer)

      alert_resolved = event.state != Event::State.lookup(Event::State::OPEN)
      alert_resolved_at = event.last_state_change_at&.to_time&.iso8601(3)&.to_time&.utc if alert_resolved

      alert_resolution = event.last_state_change_reason
      alert_resolution = Event::LastStateChangeReason.resolve(alert_resolution) || Event::LastStateChangeReason::REASON_UNKNOWN if alert_resolution.is_a?(Symbol)
      alert_resolution = nil if alert_resolution == Event::LastStateChangeReason::NO_REASON

      DependabotAlertRevision::UpdatePayload.new(
        alert_resolved:,
        alert_resolved_at:,
        alert_resolution:,
        alert_severity:,
        ghsa_id: event.ghsa_id,
        dependency_scope:,
        package_name: event.package_name,
        ecosystem: event.ecosystem,
        alert_created_at: event.created_at&.to_time&.utc,
        alert_updated_at: event.updated_at&.to_time&.utc,
      )
    end

    sig { params(severity: Symbol, repository_id: Integer, alert_number: Integer).void }
    def self.update_severities(severity, repository_id:, alert_number:)
      unless self.where(repository_id:, alert_number:).exists?
        GitHub.logger.info(
          "No revisions exist. Skipping update.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.dependabot_alerts.update.repo_id": repository_id,
          "gh.security_overview_analytics.dependabot_alerts.update.alert_number": alert_number,
          "gh.security_overview_analytics.dependabot_alerts.update.severity": severity.to_s,
        )
        return
      end

      updates = { alert_severity: severity }

      rows_updated = DependabotAlertRevision.throttle_writes_with_retry do
        DependabotAlertRevision.where(repository_id:, alert_number:).update_all(**updates)
      end

      # Recalculate rollup stats after touching a bunch of alert/revision data
      UpdateFeatureStatusSummaryJob.enqueue(repository_id:)

      GitHub.dogstats.count("security_overview_analytics.dependabot_alert_revisions.severities_updated", rows_updated)
    end

    sig { params(alert: RepositoryVulnerabilityAlert, is_initial_event: T::Boolean).returns(Event) }
    def self.create_event_payload(alert:, is_initial_event:)
      states = T.let({}, T::Hash[Symbol, T.untyped])
      created_time = alert.created_at&.iso8601(3).to_time.utc
      updated_time = alert.updated_at&.iso8601(3).to_time.utc

      if is_initial_event
        # This is the initial revision. Set alert to initial state with its creation date.
        states = {
          state: Event::State.lookup(Event::State::OPEN),
          last_state_change_at: created_time,
          updated_at: created_time,
          last_state_change_reason: Event::LastStateChangeReason.lookup(Event::LastStateChangeReason::NO_REASON)
        }
      else
        # This means we're processing the latest revision. Upsert the state as-is.
        states = {
          state: alert.state.upcase.to_sym,
          last_state_change_at: alert.last_state_change_at.iso8601(3).to_time.utc,
          updated_at: updated_time,
          last_state_change_reason: alert.last_state_change_reason&.upcase&.to_sym
        }
      end

      Event.new(
        {
          repository_id: alert.repository_id,
          repository_vulnerability_alert_id: alert.id,
          repository_vulnerability_alert_number: alert.number,
          severity: alert.severity&.upcase&.to_sym,
          ghsa_id: alert.vulnerability&.ghsa_id,
          dependency_scope: alert.dependency_scope&.upcase&.to_sym,
          package_name: alert.package_name,
          ecosystem: alert.ecosystem,
          created_at: created_time,
        }.merge(states)
      )
    end

    sig { params(repository_ids: T::Array[Integer]).void }
    def self.delete_by_repository_ids(repository_ids)
      self.where(repository_id: repository_ids).in_batches do |batch|
        batch_size = batch.size
        self.throttle_writes_with_retry do
          batch.delete_all
          GitHub.dogstats.count("security_overview_analytics.dependabot_alert_revisions.deleted", batch_size)
        end
      end
    end

    sig { override.returns(T::Array[Symbol]) }
    def self.fields_to_serialize
      UpdatePayload.props.keys
    end

    private

    sig { params(alert_resolution: T.nilable(String), revision_resolution: T.nilable(Integer)).returns(T::Boolean) }
    def resolution_reason_deviated?(alert_resolution, revision_resolution)
      return false if alert_resolution.nil? && revision_resolution.nil?
      return true if alert_resolution.nil? || revision_resolution.nil?

      alert_resolution = Event::LastStateChangeReason.resolve(alert_resolution.upcase.to_sym) || Event::LastStateChangeReason::REASON_UNKNOWN
      revision_resolution != alert_resolution
    end
  end
end
