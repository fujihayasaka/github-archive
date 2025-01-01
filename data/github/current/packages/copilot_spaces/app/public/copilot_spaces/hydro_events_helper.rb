# typed: strict
# frozen_string_literal: true

module CopilotSpaces
  module HydroEventsHelper
    extend T::Helpers

    Data = T.type_alias { T::Hash[T.any(Symbol, String), T.untyped] }
    # This module is used to send events to Hydro for copilot spaces.
    sig { params(action: String, copilot_space: CopilotSpace, current_user: User, data: Data).returns(T::Hash[Symbol, T.untyped]) }
    def self.event(action, copilot_space, current_user, data: {})
      data[:is_v3_ui_enabled] = current_user.feature_flag_enabled?(:copilot_spaces_v3_ui, default: false)
      GitHub.dogstats.distribution_time("copilot-spaces.hydro.event-payload") do
        {
          custom_copilot_id: copilot_space.id,
          custom_copilot_number: copilot_space.number,
          total_size: total_size(copilot_space),
          user_analytics_tracking_id: current_user.analytics_tracking_id,
          action: action,
          instructions_size: copilot_space.general_instructions&.size.to_i,
          errors: copilot_space.errors.full_messages,
          request_id: GitHub.context[:request_id],
          visibility: copilot_space.visibility.upcase,
          owner_type: copilot_space.owner.type,
          owner_id: copilot_space.owner.id,
          resource_count: copilot_space.resources.size,
          data:
        }
      end
    end


    sig { params(action: String, copilot_space: CopilotSpace, current_user: User, restricted_data: Data).returns(T::Hash[Symbol, T.untyped]) }
    def self.restricted_event(action, copilot_space, current_user, restricted_data: {})
      restricted_data[:is_v3_ui_enabled] = current_user.feature_flag_enabled?(:copilot_spaces_v3_ui, default: false)

      restricted_fields = {
        name: copilot_space.name,
        description: copilot_space.description,
        resources: custom_copilot_resources(copilot_space),
        instructions: copilot_space.general_instructions,
      }

      event(action, copilot_space, current_user, data: restricted_data).merge(restricted_fields)
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

    sig { params(event_name: String, current_user: User, custom_copilot: T.nilable(CopilotSpace), data: Data).void }
    def self.instrument_generic_event(event_name, current_user, custom_copilot, data: {})
      if custom_copilot.present?
        payload = event("Other", custom_copilot, current_user, data:)
      else
        payload = {
          action: "Other",
          user_analytics_tracking_id: current_user.analytics_tracking_id,
          request_id: GitHub.context[:request_id],
          data: { is_v3_ui_enabled: current_user.feature_flag_enabled?(:copilot_spaces_v3_ui, default: false) },
        }
      end
      payload[:data] = { event: event_name }.merge(data).to_json
      GlobalInstrumenter.instrument("custom_copilot.generic_event", payload)
    end


    sig { params(action: Symbol, copilot_space: CopilotSpace, current_user: User, cap_filter: T.untyped, data: Data, restricted_data: Data).void }
    def self.instrument_hydro_events(action, copilot_space, current_user, cap_filter, data: {}, restricted_data: {})
      action = action.to_s.upcase
      copilot_space.current_user = current_user if copilot_space.current_user.nil?
      copilot_space.cap_filter = cap_filter if copilot_space.cap_filter.nil?

      GlobalInstrumenter.instrument("custom_copilot.event", event(action, copilot_space, current_user, data:))
      GlobalInstrumenter.instrument("custom_copilot.restricted_event", restricted_event(action, copilot_space, current_user, restricted_data:))
    end

    sig { params(copilot_space: CopilotSpace).returns(Integer) }
    def self.total_size(copilot_space)
      copilot_space.total_content_size + copilot_space.general_instructions&.size.to_i
    end
  end
end
