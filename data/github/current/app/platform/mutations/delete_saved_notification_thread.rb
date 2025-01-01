# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteSavedNotificationThread < Platform::Mutations::Base
      extend Helpers::Newsies
      description "Deletes a saved notification thread."
      required_capabilities [:mobile_only_schema_mask, :access_internal_graphql_notifications]
      minimum_accepted_scopes ["notifications"]

      argument :id, ID, "The saved notification thread's id.", required: true, loads: Objects::NotificationThread, as: :notification_thread

      field :success, Boolean, "Did the operation succeed?", null: true
      field :viewer, Objects::User, "The user that deleted the saved notification.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, notification_thread:, **inputs)
        Platform::Objects::NotificationThread.access_allowed?(permission, notification_thread, :mark_notification)
      end

      def resolve(notification_thread:, **inputs)
        notification_thread.async_thread.then do |thread|
          response = GitHub.newsies.web.unsave_thread(context[:viewer], thread)

          raise Errors::Unprocessable.new("Unable to delete saved notification thread.") unless response.success?

          {
            success: true,
            viewer: context[:viewer],
          }
        end
      end
    end
  end
end
