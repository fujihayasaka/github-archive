# typed: strict
# frozen_string_literal: true

module Workbench
  class TelemetryInstrumenter
    sig do
      params(
        payload: Payload
      ).returns(GitHub::Result)
    end
    def self.instrument(payload)
      send_to_hydro(payload)
    end

    sig do
      params(
        payload: Payload
      ).returns(GitHub::Result)
    end
    def self.send_to_hydro(payload)
      # send event to Hydro
      if payload.restricted
        GitHub::Result.new { GlobalInstrumenter.instrument(Workbench::Events::RESTRICTED_CODESPACE, payload) }
      else
        GitHub::Result.new { GlobalInstrumenter.instrument(Workbench::Events::CODESPACE, payload) }
      end
    end

    # This payload is used for both restricted and unrestricted events.
    # It's up to the event producer to ensure the event_data is valid for the event type.
    class Payload < T::Struct
      const :context, T::Hash[T.untyped, T.untyped]
      const :event_time, Google::Protobuf::Timestamp, factory: ->() { now = Time.now; Google::Protobuf::Timestamp.new(seconds: now.to_i, nanos: now.nsec) }
      const :event_type, String
      const :request_id, String
      const :session_id, String
      const :spark_id, String
      const :user_analytics_tracking_id, String
      const :user_id, Integer
      const :restricted, T::Boolean

      sig do
        params(
          restricted: T::Boolean,
          current_user: ::User,
          event_type: String,
          request_id: String,
          session_id: String,
          spark_id: String,
          context: T::Hash[T.untyped, T.untyped],
          timestamp: T.nilable(Time),
        ).returns(Payload)
      end
      def self.from_api(restricted:, current_user:, event_type:, request_id:, session_id:, spark_id:, context:, timestamp:)
        event_time = timestamp || Time.now
        new(
          restricted:,
          context: context.merge({
            staff: current_user.employee?,
          }),
          event_time: Google::Protobuf::Timestamp.new(seconds: event_time.to_i, nanos: event_time.nsec),
          event_type: event_type,
          request_id: request_id,
          session_id: session_id,
          spark_id: spark_id,
          user_analytics_tracking_id: current_user.analytics_tracking_id || "",
          user_id: current_user.id,
        )
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def as_hydro_message
        {
          # To align with browser data, also include this in context
          context: context.merge({ "global.workbench_id": spark_id }).to_json,
          event_time: event_time,
          event_type: event_type,
          request_id: request_id,
          session_id: session_id,
          spark_id: spark_id,
          user_analytics_tracking_id: user_analytics_tracking_id,
          user_id: user_id,
          # Dup'd for better alignment with browser data
          actor_id: user_id,
        }
      end
    end
  end
end
