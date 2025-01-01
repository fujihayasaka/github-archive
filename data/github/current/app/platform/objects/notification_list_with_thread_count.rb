# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class NotificationListWithThreadCount < Platform::Objects::Base
      extend Helpers::ConditionalAccess
      description "A list of notification lists the viewer has received a notification for."
      minimum_accepted_scopes ["notifications"]
      mobile_only true

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      #
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_list.then do |list|
          (list.try(:async_owner) || list.try(:async_organization)).then do |owner|
            next false unless owner.present?

            permission.access_allowed?(
              :show_notification_list_with_thread_count,
              resource: object,
              current_repo: list.is_a?(::Repository) ? list : nil,
              current_org: owner.organization? ? owner : nil,
              allow_integrations: false,
              allow_user_via_granular_actor: false,
            )
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # indirect orgs are those that the user is not a direct member of,
        # but still needs to satisfy conditional access policies in order to view their notifications.
        # e.g. public orgs belonging to the same business that the user belongs to.
        unauthorized_account_ids = unauthorized_account_ids(permission.viewer, permission.cap_filter)
        object.async_readable_by?(permission.viewer, unauthorized_account_ids: unauthorized_account_ids)
      end

      field :list, Unions::NotificationsList, description: "Notification lists which have at least one notification with the requested status.", null: false, method: :async_list
      field :count, Integer, description: "The count of notifications for the list with any of the requested statuses.", null: false
      field :unread_count, Integer, description: "The count of notifications for the list which are unread (will be 0 if requested statuses does not include UNREAD).", null: false
    end
  end
end
