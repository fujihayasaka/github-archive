# typed: strict
# frozen_string_literal: true

module Workbench
  module WorkbenchAnalyticsEvent
    # Functions for emitting generic workbench events
    # These are utility functions to emit telemetry for generic workbench events

    # Emit a generic workbench event
    #
    # @param payload [Workbench::TelemetryInstrumenter::Payload] The payload to send to Hydro
    # @return [void]
    sig { params(payload: Workbench::TelemetryInstrumenter::Payload).void }
    def self.workbench_event(payload)
      GlobalInstrumenter.instrument(Workbench::Events::GENERIC, payload)
    end

    # Emit a restricted generic workbench event
    # Use for events that might contain sensitive information
    #
    # @param payload [Workbench::TelemetryInstrumenter::Payload] The payload to send to Hydro
    # @return [void]
    sig { params(payload: Workbench::TelemetryInstrumenter::Payload).void }
    def self.workbench_restricted_event(payload)
      GlobalInstrumenter.instrument(Workbench::Events::RESTRICTED_GENERIC, payload)
    end
  end
end
