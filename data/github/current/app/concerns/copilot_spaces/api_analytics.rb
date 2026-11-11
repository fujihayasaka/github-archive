# typed: strict
# frozen_string_literal: true

module CopilotSpaces
  module ApiAnalytics
    extend ActiveSupport::Concern
    extend T::Helpers

    requires_ancestor { Api::App }

    private

    # Track a Copilot Spaces API event via Hydro and Datadog.
    #
    # @param event_name [String] short action name (e.g. "list_spaces", "create_resource")
    # @param space [CopilotSpace, nil] the space involved, if any
    # @param extra [Hash] additional data merged into the Hydro event payload
    sig { params(event_name: String, space: T.nilable(CopilotSpace), extra: T.untyped).void }
    def track_spaces_api_event(event_name, space = nil, **extra)
      owner_type = extra.delete(:owner_type) || space&.owner&.class&.name || "unknown"
      GitHub.dogstats.increment(
        "copilot_spaces.api.request",
        tags: ["event:#{event_name}", "owner_type:#{owner_type}"]
      )

      ::CopilotSpaces::HydroEventsHelper.instrument_generic_event(
        "spaces_api.#{event_name}",
        current_user,
        space,
        data: extra.compact
      )
    end

    # Track a write operation (create/update/delete) via both Hydro event streams and Datadog.
    # Combines instrument_hydro_events (rich Hydro events) with track_spaces_api_event (counter + generic event).
    #
    # @param action [Symbol] the space-level action (:create, :update, :delete)
    # @param event_name [String] short action name for the generic event (e.g. "create_resource")
    # @param space [CopilotSpace] the space involved
    # @param hydro_data [Hash] data payload for instrument_hydro_events
    # @param extra [Hash] additional data for the generic event / dogstats
    sig { params(action: Symbol, event_name: String, space: CopilotSpace, hydro_data: T::Hash[Symbol, T.untyped], extra: T.untyped).void }
    def track_spaces_api_write_event(action:, event_name:, space:, hydro_data: {}, **extra)
      ::CopilotSpaces::HydroEventsHelper.instrument_hydro_events(action, space, current_user, cap_filter, data: hydro_data)
      track_spaces_api_event(event_name, space, **extra)
    end
  end
end
