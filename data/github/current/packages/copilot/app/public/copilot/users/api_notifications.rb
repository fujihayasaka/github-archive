# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  module Users
    module ApiNotifications
      extend T::Helpers
      include Copilot::Users::Signatures
      include Scientist

      abstract!

      # this method will iterate over the notification types to see if any exist for the user to be sent
      #
      # it gathers them all up and then sorts them by weight and returns the first one which applies
      sig { override.returns(T.nilable(Copilot::Notifications::NotificationBase)) }
      def check_notifications
        collect_metrics("api_notifications.check_notifications") do
          notifications.sort_by { |notification| notification.weight }.reverse.detect do |notification|
            begin
              notification.send_condition
            rescue StandardError => error # rubocop:todo Lint/GenericRescue
              Failbot.report(error, notification_id: notification&.notification_id)
            end
          end
        end
      end

      sig { params(notification_id: String, user_agent: String).returns(T::Boolean) }
      def acknowledge_notification(notification_id, user_agent: "")
        collect_metrics("copilot.acknowledge_notification") do
          notification = Copilot::EditorNotification.where(notification_id: notification_id, user_id: user_object.id).first

          return false unless notification.present?
          return false if notification.acknowledged?

          Copilot::Instrumenter.instrument_editor_notification_acknowledged(copilot_user_object, notification.notification_id)

          GitHub.dogstats.increment(
            "copilot.notification",
            tags: ["event:acknowledged"],
          )
          ActiveRecord::Base.connected_to(role: :writing) do
            notification.acknowledge
          end
        end
      end

      private

      def notifications
        return @notifications if defined?(@notifications)

        @notifications = Copilot::EditorNotification::COPILOT_NOTIFICATION_TYPES.keys.map do |notification_id|
          "Copilot::Notifications::#{notification_id.to_s.camelize}".constantize.new(self)
        end
      end
    end
  end
end
