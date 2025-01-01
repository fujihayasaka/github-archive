# typed: strict
# frozen_string_literal: true

module Copilot
  class UserCleaner < Command

    sig { params(user_id: Integer).void }
    def initialize(user_id)
      @user_id = user_id
    end

    # this is for a user that has been deleted or is spammy
    # we are gonna viciously remove all the seats and seat assignments and configurations
    sig { override.void }
    def perform
      GitHub.logger.with_named_tags("gh.user.id" => @user_id) do
        if user_can_be_cleaned?
          with_write do
            seat_ids = Set.new
            Copilot::Seat.where(assigned_user_id: @user_id).each do |seat|
              GitHub.logger.info(
                "Destroying seat",
                "gh.copilot.seat.id" => seat.id,
                "gh.copilot.seat.assigned_user_id" => seat.assigned_user_id,
                "gh.copilot.seat.copilot_seat_assignment_id" => seat.copilot_seat_assignment_id,
              )
              seat_ids << seat.id
              seat.cancel!(reason: :user_cleaned) # Notify the user that their seat has been removed, if they exist
            end
            GitHub.logger.info("Destroyed seats", "gh.copilot.seats.count" => seat_ids.count)
            seat_ids = seat_ids.to_a

            deleted_copilot_activities = Copilot::Activity.where(copilot_seat_id: seat_ids).destroy_all
            GitHub.logger.info("Destroyed copilot activities", "gh.copilot.activities.count" => deleted_copilot_activities.count)

            deleted_copilot_activity_histories = Copilot::ActivityHistory.where(copilot_seat_id: seat_ids).destroy_all
            GitHub.logger.info("Destroyed copilot activity histories", "gh.copilot.activity_histories.count" => deleted_copilot_activity_histories.count)

            deleted_copilot_authentications = Copilot::Authentication.where(copilot_seat_id: seat_ids).destroy_all
            GitHub.logger.info("Destroyed copilot authentications", "gh.copilot.authentications.count" => deleted_copilot_authentications.count)

            deleted_copilot_authentication_histories = Copilot::AuthenticationHistory.where(copilot_seat_id: seat_ids).destroy_all
            GitHub.logger.info("Destroyed copilot authentication histories", "gh.copilot.authentication_histories.count" => deleted_copilot_authentication_histories.count)

            # this may not be necessary (since cancelling the seat calls the destroy_when_empty on the seat assignment)
            deleted_seat_assignments = Copilot::SeatAssignment.where(assignable_type: "User", assignable_id: @user_id).destroy_all
            GitHub.logger.info("Destroyed user seat assignments", "gh.copilot.seat_assignments.count" => deleted_seat_assignments.count)

            deleted_configurations = Copilot::Configuration.where(configurable_type: "User", configurable_id: @user_id).destroy_all
            GitHub.logger.info("Destroyed configurations", "gh.copilot.configurations.count" => deleted_configurations.count)

            deleted_free_users = Copilot::FreeUser.where(user_id: @user_id).destroy_all
            GitHub.logger.info("Destroyed free users", "gh.copilot.free_users.count" => deleted_free_users.count)

            deleted_limited_users = Copilot::LimitedUser.where(user_id: @user_id).destroy_all
            GitHub.logger.info("Destroyed limited users", "gh.copilot.limited_users.count" => deleted_limited_users.count)

            deleted_notifications = Copilot::EditorNotification.where(user_id: @user_id).destroy_all
            GitHub.logger.info("Destroyed editor notifications", "gh.copilot.editor_notifications.count" => deleted_notifications.count)

            deleted_details = Copilot::AggregateUsageDetail.where(user_id: @user_id).destroy_all
            GitHub.logger.info("Destroyed aggregate usage details", "gh.copilot.aggregate_usage_details.count" => deleted_details.count)

            deleted_technical_preview_users = Copilot::TechnicalPreviewUser.where(user_id: @user_id).destroy_all
            GitHub.logger.info("Destroyed technical preview users", "gh.copilot.technical_preview_users.count" => deleted_technical_preview_users.count)
          end
        else
          GitHub.logger.info("User cannot be cleaned")
          Copilot::ErrorReporter.report!(
            Copilot::Errors::UserCannotBeCleanedError.new("User cannot be cleaned"),
            extra_details: { "gh.user.id" => @user_id },
          )
        end
      end
    end

    sig { returns(T::Boolean) }
    def user_can_be_cleaned?
      user = ::User.find_by(id: @user_id)
      if user.present?
        GitHub.logger.info(
          "User exists",
          "gh.user.spammy" => user.spammy?,
        )
        user.spammy?
      else
        GitHub.logger.info("User does not exist, continuing")
        true
      end
    end
  end
end
