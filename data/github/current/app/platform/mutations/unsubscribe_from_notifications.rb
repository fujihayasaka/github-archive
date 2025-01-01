# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnsubscribeFromNotifications < Platform::Mutations::Base
      extend Helpers::Newsies

      description "Unsubscribes from notifications"
      required_capabilities [:access_internal_graphql_notifications]
      minimum_accepted_scopes ["notifications"]

      argument :ids, [ID], "The NotificationThread IDs of the objects to unsubscribe from.", required: true, loads: Interfaces::Subscribable, as: :notification_threads

      field :success, Boolean, "Did the operation succeed?", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        permission.can_list_user_notifications?(permission.viewer)
      end

      def resolve(notification_threads:, **inputs)
        if notification_threads.count > Platform::Models::NotificationThread::LIMIT_ACTIONS_PER_USER
          raise Errors::ArgumentLimit.new("You can only unsubscribe from #{Platform::Models::NotificationThread::LIMIT_ACTIONS_PER_USER} notifications as unread.")
        end

        begin
          notification_threads.each do |notification_thread|
            GitHub.newsies.process_subscription_update(
              subscribable: notification_thread,
              state: "unsubscribed",
              user: context[:viewer]
            )
          end
        rescue ArgumentError => e
          raise Errors::Validation.new(e.message)
        end

        {
          success: true,
        }
      end
    end
  end
end
