# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MarkNotificationsAsUndone < Platform::Mutations::Base
      extend Helpers::Newsies

      description "Marks a notification as undone"
      required_capabilities [:mobile_only_schema_mask, :access_internal_graphql_notifications]
      minimum_accepted_scopes ["notifications"]

      argument :ids, [ID], "The NotificationThread IDs to be marked as undone.", required: true, loads: Objects::NotificationThread, as: :notification_threads

      field :success, Boolean, "Did the operation succeed?", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # This function uses a simplified permissions check as it avoids duplicate efforts while checking for viewer access.
      # Permissions are already being checked while loading in the IDs as a `NotificationThread`, and while calling `mark_summaries_as_read`.
      def self.async_api_can_modify?(permission, **inputs)
        permission.can_list_user_notifications?(permission.viewer)
      end

      def resolve(notification_threads:, **inputs)
        if notification_threads.count > Platform::Models::NotificationThread::LIMIT_ACTIONS_PER_USER
          raise Errors::ArgumentLimit.new("You can only mark up to #{Platform::Models::NotificationThread::LIMIT_ACTIONS_PER_USER} notifications as done.")
        end

        summary_ids = notification_threads.map(&:summary_id)

        self.class.unpack_newsies_response!(
          GitHub.newsies.web.mark_summaries_as_read(context[:viewer], summary_ids),
        )

        {
          success: true,
        }
      end
    end
  end
end
