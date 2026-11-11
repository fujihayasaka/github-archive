# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MarkNotificationAsDone < Platform::Mutations::Base
      docs_category :activity
      extend Helpers::Newsies

      description "Marks a notification as done"
      required_capabilities [:mobile_only_schema_mask, :access_internal_graphql_notifications]
      minimum_accepted_scopes ["notifications"]

      argument :id, ID, "The NotificationThread id.", required: true, loads: Objects::NotificationThread, as: :notification_thread

      field :success, Boolean, "Did the operation succeed?", null: true
      field :viewer, Objects::User, "The user that the notification belongs to.", null: true
      field :notification_thread, Objects::NotificationThread,
        null: true,
        description: "The notification thread after update.",
        visibility: :internal

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, notification_thread:, **inputs)
        Platform::Objects::NotificationThread.access_allowed?(permission, notification_thread, :mark_notification)
      end

      def resolve(notification_thread:, **inputs)
        self.class.unpack_newsies_response!(
          GitHub.newsies.web.mark_summaries_as_archived(context[:viewer], [notification_thread.summary_id]),
        )

        if FeatureFlag.vexi.enabled?(:notifications_deprecate_load_from_global_id, context[:viewer], default: false)
          global_id = Platform::Helpers::GlobalId.parse(notification_thread.next_global_id)

          {
            success: true,
            notification_thread: Platform::Objects::NotificationThread.load_from_next_global_id(global_id), # reload the notification thread object
            viewer: context[:viewer],
          }
        else
          {
            success: true,
            notification_thread: Platform::Objects::NotificationThread.load_from_global_id(notification_thread.id), # reload the notification thread object
            viewer: context[:viewer],
          }
        end
      end
    end
  end
end
