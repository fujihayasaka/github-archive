# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  module Notifications
    class CopilotSeatAdded < NotificationBase
      def message
        "The organization #{organization_login} has granted you access to GitHub Copilot."
      end

      def notification_id
        notification_ids_to_send.any? ? notification_ids_to_send.first[0] : "copilot_seat_added_none"
      end

      def send_condition
        super do
          # we need to load up all of the Seats for the user and see if any of them have not been sent a notification yet
          return false if seat_and_organization_ids.empty?

          notification_ids_to_send.any?
        end
      end

      private

      def organization_login
        @organization_login ||= ::Organization.find(notification_ids_to_send.first[1]).display_login
      end

      def seat_and_organization_ids
        # for right now, this will only be sent for organization based
        @seat_ids ||= Copilot::Seat.where(assigned_user_id: copilot_user.id).where.not(organization_id: nil).pluck(:id, :organization_id)
      end

      def notification_and_organization_ids
        @notification_ids ||= seat_and_organization_ids.map { |id, organization_id| ["copilot_seat_added_#{id}", organization_id] }
      end

      def existing_notification_ids
        @existing_notifications_ids ||= Copilot::EditorNotification.where(notification_id: notification_and_organization_ids.map(&:first), user_id: copilot_user.id).pluck(:notification_id)
      end

      def notification_ids_to_send
        @notification_ids_to_send ||= notification_and_organization_ids.reject { |id, _organization_id| existing_notification_ids.include?(id) }
      end
    end
  end
end
