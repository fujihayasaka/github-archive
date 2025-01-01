# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateNotificationSettings < Platform::Mutations::Base
      include Helpers::Newsies

      description "Updates the user's notification settings."
      minimum_accepted_scopes ["user"]
      required_capabilities [:mobile_only_schema_mask]

      argument :gets_participating_web,
        Boolean,
        "Does the viewer get web notifications for threads in which they are participating?",
        required: false

      argument :gets_watching_web,
        Boolean,
        "Does the viewer get web notifications for threads which they are watching or to which they are subscribed?",
        required: false

      argument :gets_vulnerability_alerts_web,
        Boolean,
        "Does the viewer get web notifications for vulnerability alerts?",
        required: false

      argument :gets_direct_mention_mobile_push,
        Boolean,
        "Does the viewer get mobile push notifications for comments in which they are directly mentioned?",
        required: false

      field :success, Boolean, "Did the operation succeed?", null: true
      field :viewer, Objects::User, "The user whose settings were updated.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        user = permission.viewer
        permission.access_allowed?(
          :update_user_notification_settings,
          resource: user,
          current_org: nil,
          current_repo: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false,
        )
      end

      def resolve(**inputs)
        viewer = context[:viewer]
        gets_participating_web = inputs[:gets_participating_web]
        gets_watching_web = inputs[:gets_watching_web]
        gets_vulnerability_alerts_web = inputs[:gets_vulnerability_alerts_web]
        gets_direct_mention_mobile_push = inputs[:gets_direct_mention_mobile_push]

        if !Notifications::Settings.set_web(viewer,
          watcher: gets_watching_web,
          participant: gets_participating_web,
          vulnerability: gets_vulnerability_alerts_web,
        )
          raise Errors::ServiceUnavailable.new("Notifications features are currently unavailable.")
        end

        # keep new mobile push notification table in sync until it's fully migrated to
        errors = []
        unless gets_direct_mention_mobile_push.nil?
          mobile_push_settings = viewer.mobile_push_notification_setting || MobilePushNotificationSetting.create(user: viewer)
          mobile_push_settings.direct_mention = gets_direct_mention_mobile_push
          if !mobile_push_settings.save
            errors << Platform::UserErrors.mutation_errors_for_model(mobile_push_settings)
          end
        end

        {
          success: true,
          viewer: context[:viewer],
          errors: errors
        }
      end
    end
  end
end
