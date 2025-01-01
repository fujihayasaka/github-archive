# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MobileEventsUpdate < Platform::Mutations::Base
      description "Sends a batch of hydro analytics for a user."
      required_capabilities [:mobile_only_schema_mask]
      minimum_accepted_scopes ["user"]

      argument :events_batch, [Inputs::MobileHydroEvent], "An array of hydro events.", required: true

      field :user, Objects::User, "The user who posted the events.", null: true

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(:update_user, resource: permission.viewer,
                                   current_repo: nil, current_org: nil,
                                   allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(**inputs)
        inputs[:events_batch].each do |event|
          hydro_payload = {
            actor: context[:viewer],
            application: event[:app_type],
            element: event[:app_element],
            action: event[:action],
            device: event[:device_type],
            performed_at: event[:performed_at],
            subject_type: event[:subject_type],
            context: event[:extra_context]
          }

          GlobalInstrumenter.instrument("mobile.event", hydro_payload)
        end

        { user: context[:viewer] }
      end
    end
  end
end
