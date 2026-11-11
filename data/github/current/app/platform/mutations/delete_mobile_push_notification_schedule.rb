# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteMobilePushNotificationSchedule < Platform::Mutations::Base
      include Helpers::Newsies

      description "Delete a mobile push notification schedule."
      minimum_accepted_scopes ["user"]
      required_capabilities [:mobile_only_schema_mask]

      argument :id, ID, "The Node ID of the mobile push notification schedule to be deleted.",
        required: true, loads: Objects::MobilePushNotificationSchedule, as: :schedule

      field :success, Boolean, "Did the operation succeed?", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      #
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, *_)
        permission.access_allowed?(
          :update_user_notification_settings,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false,
        )
      end

      def resolve(schedule:)
        if schedule.user != @context[:viewer]
          raise Errors::NotFound.new("Could not resolve to a node with the global id of '#{schedule.global_relay_id}'")
        end

        destroyed_schedule = handle_newsies_service_unavailable do
          schedule.destroy
        end

        unless destroyed_schedule.destroyed?
          raise Errors::Unprocessable.new(destroyed_schedule.errors.full_messages.to_sentence)
        end

        { success: true }
      end
    end
  end
end
