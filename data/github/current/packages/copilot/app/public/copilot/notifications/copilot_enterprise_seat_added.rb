# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  module Notifications
    class CopilotEnterpriseSeatAdded < NotificationBase

      include GitHub::Memoizer

      sig { returns(String) }
      def message
        "The enterprise #{enterprise_login} has granted you access to GitHub Copilot."
      end

      sig { returns(String) }
      def notification_id
        existing_notification_ids.any? ? "copilot_enterprise_seat_added_none" : existing_id
      end

      sig { returns(T::Boolean) }
      def send_condition
        super do
          # this is for standalone businesses only, so this single business is associated with the seat, nothing else
          return false unless copilot_user.has_copilot_standalone_business?

          # copilot_enterprise_seat_added_none is not a valid notification_id in the DB, so no point in sending it
          # since the user won't be able to aknowledge it
          return false if notification_id == "copilot_enterprise_seat_added_none"

          existing_notification_ids.count == 0
        end
      end

      private

      sig { returns(String) }
      def enterprise_login
        login = granting_enterprise&.slug

        # This really should never happen, but it is technically possible as granting_enterprise can return nil
        Failbot.report("Standalone seat added without granting enterprise", { "gh.user.id" => copilot_user.id }) if login.nil?

        login || "unknown enterprise"
      end

      sig { returns(T::Array[String]) }
      def existing_notification_ids
        return [] unless copilot_user.has_copilot_standalone_business?

        @existing_notifications_ids ||= Copilot::EditorNotification.where(
          notification_id: existing_id,
          user_id: copilot_user.id
        ).pluck(:notification_id)
      end

      sig { returns(String) }
      def existing_id
        if copilot_user.has_copilot_standalone_business? && granting_enterprise.nil?
          "copilot_enterprise_seat_added_none"
        else
          "copilot_enterprise_seat_added_#{granting_enterprise&.id}"
        end
      end

      # Because we don't know which of the potentially several enterprises has granted the seat,
      # we need to look at all of them and determine the most recent one.
      sig { returns(T.nilable(::Business)) }
      memoize def granting_enterprise
        return nil unless copilot_user.has_copilot_standalone_business?

        # first, load up all the standalone businesses for the user
        copilot_user.copilot_standalone_businesses.flat_map do |biz|
          # next, get each seat assignment for the business
          Copilot::SeatAssignment.for_standalone_business(biz.__getobj__).filter do |assignment|
            # we are only interested in assignments that have been assigned to the user
            # Note that we have to use an assignment here because this method will likely be called before seat creation

            case assignment.assignable_type
            when "EnterpriseTeam"
              assignment.assignable.member_by_id?(copilot_user.id)
            else
              false
            end
          end
        end.sort_by(&:created_at).last&.owner # finally, grab the most recent enterprise that has granted a seat to the user
      end
    end
  end
end
