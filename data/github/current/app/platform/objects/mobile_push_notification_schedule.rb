# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MobilePushNotificationSchedule < Platform::Objects::Base
      model_name "Newsies::MobilePushNotificationSchedule"
      description "A push notifications schedule for a user."

      minimum_accepted_scopes ["user"]
      required_capabilities [:mobile_only_schema_mask]

      implements_node templates: [[:umpn, :user_id, :mobile_push_notification_schedule_id]], as: "MPN", ready_date: "2021-06-18" do |mobile_push_notification_schedule|
        {
          prefix: :umpn,
          user_id: mobile_push_notification_schedule.user_id,
          mobile_push_notification_schedule_id: mobile_push_notification_schedule.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      #
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _)
        permission.access_allowed?(
          :read_user_notification_settings,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false,
        )
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # we only want to allow users to view their own schedules for now
        object.user_id == permission.viewer&.id
      end

      field :day, Enums::DayOfWeek, description: "The schedule day.", null: false

      field :start_time, Scalars::MobilePushScheduleTime, description: "The schedule start time (0:00..23:59)", null: false
      field :end_time, Scalars::MobilePushScheduleTime, description: "The schedule end time (0:00..23:59)", null: false

      field :time_zone, String, description: "The user's time zone name", null: false

      def time_zone
        @context[:viewer].async_mobile_time_zone.then(&:name)
      end
    end
  end
end
