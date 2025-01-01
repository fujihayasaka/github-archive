# typed: strict
# frozen_string_literal: true

module Copilot
  module Notifications
    class CopilotSeatRemoved < NotificationBase

      include GitHub::Memoizer

      sig { returns(String) }
      def message
        "Your GitHub Copilot access has been disabled by the organization #{organization_login}."
      end

      sig { returns(T::Boolean) }
      def send_condition
        super do
          # this will never catch the `existing?` call in the super because we're looking for something with the organization id attached
          pending_notifications.any?
        end
      end

      private

      sig { returns(String) }
      memoize def organization_login
        return "" unless pending_notifications.any?

        pending_organization_id = T.must(pending_notifications.first).notification_id.split("_").last
        organization = ::Organization.find_by(id: pending_organization_id)
        return "" unless organization.present?

        organization.display_login
      end

      sig { returns(T::Array[Copilot::EditorNotification]) }
      def pending_notifications
        Copilot::EditorNotification.where(user_id: copilot_user.id).where("notification_id LIKE ?", "copilot_seat_removed_%").to_a
      end
    end
  end
end
