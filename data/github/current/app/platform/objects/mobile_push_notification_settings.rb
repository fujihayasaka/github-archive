# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MobilePushNotificationSettings < Platform::Objects::Base
      model_name "MobilePushNotificationSetting"
      description "The viewer's mobile push notification settings"

      minimum_accepted_scopes ["user"]
      mobile_only true

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
        # we only want to allow users to view their own settings
        permission.viewer&.id == object.user_id
      end

      field :gets_direct_mentions, Boolean,
        description: "Does the viewer get mobile push notifications for comments in which they are directly mentioned?",
        method: :direct_mention?,
        null: false

      field :gets_assignments, Boolean,
        description: "Does the viewer get mobile push notifications for issues or pull requests in which they assigned?",
        method: :assignments?,
        null: false

      field :gets_review_requests, Boolean,
        description: "Does the viewer get mobile push notifications for pull requests in which their review was requested?",
        method: :review_requests?,
        null: false

      field :gets_deployment_requests, Boolean,
        description: "Does the viewer get mobile push notifications for deployment requests?",
        method: :deployment_requests?,
        null: false

      field :scheduled_notifications, Boolean,
        description: "Does the viewer have scheduled push notifications enabled/disabled?",
        method: :scheduled_notifications?,
        null: false

      field :gets_pull_request_reviews, Boolean,
        description: "Does the viewer get mobile push notifications when their pull requests have been reviewed?",
        method: :pull_request_reviews?,
        null: false

      field :gets_ci_activity, Boolean,
        description: "Does the viewer get mobile push notifications when their CI activity state changes?",
        method: :ci_activity?,
        null: false

      field :gets_ci_failed_only, Boolean,
        description: "Does the viewer get mobile push notifications for CI activity only when it fails?",
        method: :ci_failed_only?,
        null: false

      field :gets_releases, Boolean,
        description: "Does the viewer get mobile push notifications for watched repository releases?",
        method: :releases?,
        null: false
    end
  end
end
