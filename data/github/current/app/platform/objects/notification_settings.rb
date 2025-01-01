# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class NotificationSettings < Platform::Objects::Base
      description "The viewer's notification settings"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
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
        # `object` here is an instance of `Newsies::Settings`, so `object.id` is actually a User ID.
        permission.viewer&.id == object.id
      end

      minimum_accepted_scopes ["user"]
      required_capabilities [:mobile_only_schema_mask]

      field :gets_participating_web,
        Boolean,
        description: "Does the viewer get web notifications for threads in which they are participating?",
        method: :participating_web?,
        null: false

      field :gets_participating_email,
        Boolean,
        description: "Does the viewer get email notifications for threads in which they are participating?",
        method: :participating_email?,
        null: false

      field :gets_watching_web,
        Boolean,
        description: "Does the viewer get web notifications for threads which they are watching or to which they are subscribed?",
        method: :subscribed_web?,
        null: false

      field :gets_watching_email,
        Boolean,
        description: "Does the viewer get email notifications for threads which they are watching or to which they are subscribed?",
        method: :subscribed_email?,
        null: false

      field :gets_direct_mention_mobile_push,
        Boolean,
        description: "Does the viewer get mobile push notifications for comments in which they are directly mentioned?",
        null: false

      def gets_direct_mention_mobile_push
        @object.async_user.then do |user|
          @object.direct_mention_mobile_push? || MobilePushNotificationSetting.where(user_id: user.id, direct_mention: true).exists?
        end
      end

      field :gets_vulnerability_alerts_web,
        Boolean,
        description: "Does the viewer get web notifications for vulnerability alerts?",
        method: :vulnerability_web?,
        null: false

      field :enabled_ci_notifications,
        Boolean,
        description: "Did the view enable notifications for continuous integration activity?",
        method: :continuous_integration_enabled?,
        null: false

      field :notifiable_emails,
        [String],
        description: "The email addresses belonging to this user that can receive notifications.",
        null: false

      def notifiable_emails
        @object.async_user.then do |user|
          user.notifiable_emails.map(&:downcase)
        end
      end

      # This method is using agnostic 'grouped list' language as the underlying framework uses it as well
      # Current implementation in our UI is to group by repository.
      field :gets_user_prefers_list_grouped,
        Boolean,
        description: "Does the viewer prefer to receive notifications in a grouped list?",
        null: false,
        visibility: :internal

      def gets_user_prefers_list_grouped
        @object.async_user.then do |user|
          user.prefer_notifications_grouped_by_list?
        end
      end
    end
  end
end
