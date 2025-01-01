# typed: strict
# frozen_string_literal: true

module CopilotSpaces
  module HydroEventsHelper
    extend T::Helpers
    # This module is used to send events to Hydro for custom copilots.
    sig { params(action: String, copilot_space: CopilotSpace, current_user: User, request: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def self.event(action, copilot_space, current_user, request)
      {
        custom_copilot_id: copilot_space.id,
        custom_copilot_uuid: copilot_space.uuid || "",
        custom_copilot_number: copilot_space.number,
        total_size: total_size(copilot_space),
        user_analytics_tracking_id: current_user.analytics_tracking_id,
        action: action,
        instructions_size: copilot_space.general_instructions&.size.to_i,
        errors: copilot_space.errors.full_messages,
        request_id: GitHub.context[:request_id],
        visibility: copilot_space.visibility.upcase,
        owner: copilot_space.owner
      }
    end


    sig { params(action: String, copilot_space: CopilotSpace, current_user: User, request: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def self.restricted_event(action, copilot_space, current_user, request)
      restricted_fields = {
        name: copilot_space.name,
        description: copilot_space.description,
        resources: custom_copilot_resources(copilot_space),
        instructions: copilot_space.general_instructions,
      }

      event(action, copilot_space, current_user, request).merge(restricted_fields)
    end

    sig { params(copilot_space: CopilotSpace).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.custom_copilot_resources(copilot_space)
      copilot_space.resources.map do |resource|
        {
          name: resource.restricted_hydro_file_name,
          type: resource.resource_type,
          size: resource.size,
        }
      end
    end


    sig { params(action: Symbol, copilot_space: CopilotSpace, current_user: User, request: T.untyped, cap_filter: T.untyped).void }
    def self.instrument_hydro_events(action, copilot_space, current_user, request, cap_filter)
      action = action.to_s.upcase
      copilot_space.current_user = current_user if copilot_space.current_user.nil?
      copilot_space.cap_filter = cap_filter if copilot_space.cap_filter.nil?

      GlobalInstrumenter.instrument("custom_copilot.event", event(action, copilot_space, current_user, request))
      GlobalInstrumenter.instrument("custom_copilot.restricted_event", restricted_event(action, copilot_space, current_user, request))
    end

    sig { params(copilot_space: CopilotSpace).returns(Integer) }
    def self.total_size(copilot_space)
      copilot_space.total_content_size + copilot_space.general_instructions&.size.to_i
    end
  end
end
