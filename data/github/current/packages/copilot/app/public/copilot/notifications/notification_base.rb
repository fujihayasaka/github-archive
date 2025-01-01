# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  module Notifications
    class NotificationBase
      attr_reader :copilot_user

      # make sure that the copilot_user is a Copilot::User
      def initialize(copilot_user)
        @copilot_user = copilot_user.is_a?(Copilot::User) ? copilot_user : Copilot::User.new(copilot_user)
      end

      # This method returns a boolean whether the record can be deleted
      # - notifications can be deleted if they have been acknowledged and it doesn't need to persist
      def delete_condition
        false
      end

      # This is the link to be sent down in the notification response
      def link
        Copilot::Envelope::SETTINGS_PAGE
      end

      # Text to be sent to the user, must be implemented in the subclass
      def message
        raise NotImplementedError, "Must implement #message."
      end

      # the title is what shows up on the button in the notification
      def title
        "Copilot Settings"
      end

      # This is unique for each notification, but reusable across users
      def notification_id
        self.class.name.to_s.underscore.gsub("copilot/notifications/", "")
      end

      # This method returns a boolean whether the record should be sent in the response body
      def send_condition
        org = @copilot_user.copilot_organization
        return false if Copilot.copilot_communication_opt_out?(org&.organization_object)

        return false if existing?
        yield if block_given?
      end

      # A few of the notification types should be shown first. A higher number here will make them show up first.
      # Max is 100
      def weight
        0
      end

      # Since this is the same structure for everyone, put it here
      def envelope_data
        {
          message: message,
          url: link,
          title: title,
          notification_id: notification_id
        }
      end

      # since this will never be more than seven and we don't il8it, we can just use a case statement
      def numbers_to_words(number)
        case number
        when 7
          "seven"
        when 6
          "six"
        when 5
          "five"
        when 4
          "four"
        when 3
          "three"
        when 2
          "two"
        when 1
          "one"
        when 0
          "zero"
        end
      end

      # This method returns a boolean whether a record exists (acknowledged or not) for the user
      def existing?
        Copilot::EditorNotification.where(notification_id: notification_id, user_id: copilot_user.id).exists?
      end

      # This method returns a boolean whether a specific EditorNotification has been acknowledged for the user
      def existing_acknowledged?
        Copilot::EditorNotification.
          where(notification_id: notification_id, user_id: copilot_user.id).
          where("acknowledged_at IS NOT NULL").exists?
      end

      # this tries to store the created notification
      def store
        ActiveRecord::Base.connected_to(role: :writing) do
          Copilot::EditorNotification.create(
            notification_id: notification_id,
            user_id: copilot_user.id
          )
        end
      rescue ActiveRecord::RecordNotUnique
        # It's possible that another request has come through and created this record
        # That's okay, we'll be fine.
        GitHub.dogstats.increment("copilot.notifications.duplicate_notification")
        nil
      end
    end
  end
end
