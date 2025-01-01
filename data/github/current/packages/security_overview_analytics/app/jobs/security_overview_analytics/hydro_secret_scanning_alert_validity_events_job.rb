# typed: strict
# frozen_string_literal: true

require "secret_scanning_proto"
require "hydro/schemas/token_scanning_service/v0/alert_events_pb"

module SecurityOverviewAnalytics
  class HydroSecretScanningAlertValidityEventsJob < HydroMessageJob
    include GitHub::Memoizer
    include LifecycleEventHandler::Hydro
    include LifecycleEventRetryHandler

    queue_as :hydro_security_overview_analytics_secret_scanning_alert_validity_events

    retry_on_dirty_exit

    SecretScanningTokenValidity = ::GitHub::Proto::SecretScanning::Types::V1::TokenValidity
    EventPayload = ::Hydro::Schemas::TokenScanningService::V0::AlertEvents
    AlertEvent = ::Hydro::Schemas::TokenScanningService::V0::AlertEvents::AlertEvent
    EventTypes = ::Hydro::Schemas::TokenScanningService::V0::AlertEvents::AlertEvent::EventType

    resolve_tenant_context do |message|
      ::Repositories::Public.resolve_tenant(id: message.dig(:repository_id))
    end

    sig { void }
    def perform
      unless event_type == EventTypes::ALERT_VALIDATED
        report_event_skipped("unsupported_event")
        return
      end

      if repository.deleted?
        report_event_skipped("repository_deleted")
        return
      end

      unless TenantValidationHelper.should_handle_secret_scanning_alert_events?(repository.owner)
        report_event_skipped("tenant_not_in_scope")
        return
      end

      # Use event timestamp for date_id and updated_at
      updated_fields = {
        alert_validity:,
        alert_updated_at: event_time,
      }

      SecretScanningAlertRevision.throttle_writes_with_retry do
        SecretScanningAlertRevision.upsert_revision_with_fields(
          updated_fields,
          repository_id:,
          alert_number:
        )
      end

      instrument_event_processed
    end

    protected

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.id": repository_id,
        "gh.security_overview_analytics.alert_number": alert_number,
        "gh.security_overview_analytics.alert_validity": alert_validity,
        "gh.security_overview_analytics.event_time": timestamp,
      })
    end

    private

    sig { override.returns(String) }
    def source_event
      schema
    end

    sig { returns(EventPayload) }
    memoize def event_payload
      EventPayload.new(message)
    end

    sig { returns(AlertEvent) }
    memoize def alert_event
      event_payload.events.first
    end

    sig { returns(T.nilable(Integer)) }
    def event_type
      event_type = alert_event.event
      if event_type.is_a?(Symbol)
        EventTypes.resolve(event_type)
      else
        event_type
      end
    end

    sig { returns(Integer) }
    def repository_id
      event_payload.repository_id
    end

    sig { returns(Integer) }
    def alert_number
      alert_event.alert_number
    end

    sig { returns(T.nilable(Integer)) }
    def alert_validity
      validity = alert_event.token_validity

      if validity.is_a?(Symbol) && validity != :TOKEN_VALIDITY_UNKNOWN
        SecretScanningTokenValidity.resolve(validity)
      elsif validity.is_a?(Integer) && validity != 0
        validity
      end
    end

    sig { returns(::Repository) }
    def repository
      ::Repositories::Public.get_active_or_deleted!(repository_id)
    end

    sig { override.returns(Time) }
    memoize def event_time
      Time.at(timestamp_nano).utc
    end

    sig { void }
    def instrument_event_processed
      instrument_repository_updated

      elapsed_time = (Time.now.to_f - timestamp) * 1_000
      GitHub.logger.info(
        "Secret scanning alert event processed",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_overview_analytics.revision.elapsed_time": elapsed_time,
      )
    end

    sig { params(reason: String).void }
    def report_event_skipped(reason)
      GitHub.dogstats.increment(
        "security_overview_analytics.secret_scanning_alert_validity_event.skipped",
        tags: all_stats_tags + [
          "reason:#{reason.parameterize.underscore}"
        ]
      )
      GitHub.logger.info(
        "Validity event ingestion skipped.",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_overview_analytics.job.reason": reason,
      )
    end
  end
end
