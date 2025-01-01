# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateMobilePushNotificationSchedules < Platform::Mutations::Base
      include Helpers::Newsies

      description "Update existing mobile push notification schedules."
      minimum_accepted_scopes ["user"]
      required_capabilities [:mobile_only_schema_mask]

      argument :days, [Enums::DayOfWeek], "The days of the week for the schedule.", required: true
      argument :start_time, Scalars::MobilePushScheduleTime, "The schedule start time (0:00..23:59)", required: true
      argument :end_time, Scalars::MobilePushScheduleTime, "The end start time (0:00..23:59)", required: true

      error_fields
      field :mobile_push_notification_schedules, [Objects::MobilePushNotificationSchedule], "The updated mobile push notification schedules.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(
          :update_user_notification_settings,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false,
        )
      end

      def resolve(days:, start_time:, end_time:)
        if days.uniq != days
          return {
            mobile_push_notification_schedules: [],
            errors: [{
              "path" => %w[input days],
              "message" => "Multiple schedules are not supported for the same day",
            }],
          }
        end

        current_schedules = ::Newsies::MobilePushNotificationSchedule.where(user_id: @context[:viewer].id)
        attributes = days.map do |day|
          {
            day: day,
            start_time: start_time,
            end_time: end_time,
            user_id: @context[:viewer].id
          }
        end

        schedules = handle_newsies_service_unavailable do
          ::Newsies::MobilePushNotificationSchedule.transaction do
            current_schedules.destroy_all if current_schedules.present?

            ::Newsies::MobilePushNotificationSchedule.create(attributes)
          end
        end

        valid_schedules = schedules.select(&:persisted?)
        invalid_schedules = schedules - valid_schedules
        error_messages = invalid_schedules.map { |schedule| schedule.errors.full_messages.join(", ") }

        {
          mobile_push_notification_schedules: valid_schedules,
          errors: invalid_schedules.map do |schedule|
            Platform::UserErrors.mutation_errors_for_model(schedule, translate: { day: "days" })
          end.flatten
        }
      end
    end
  end
end
