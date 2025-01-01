# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateMobilePushNotificationSettings < Platform::Mutations::Base
      description "Update mobile push notification settings."
      minimum_accepted_scopes ["user"]
      mobile_only true

      argument :get_direct_mentions, Boolean, "If the user would like to receive direct mentions.", required: false
      argument :get_assignments, Boolean, "If the user would like to receive assignments.", required: false
      argument :get_review_requests, Boolean, "If the user would like to receive review requests.", required: false
      argument :get_deployment_requests, Boolean, "If the user would like to receive deployment requests.", required: false
      argument :get_pull_request_reviews, Boolean, "If the user would like to receive pull request reviews.", required: false
      argument :scheduled_notifications, Boolean, "If the user currently has a push notification schedule enabled/disabled (e.g., working hours).", required: false
      argument :get_ci_activity, Boolean, "If the user would like to receive CI activity.", required: false
      argument :get_ci_failed_only, Boolean, "If the user would like to receive CI activity only for failed workflows.", required: false
      argument :get_releases, Boolean, "If the user would like to receive push notifications for watched repository releases", required: false

      error_fields
      field :user, Objects::User, "The user whose push settings will be updated.", null: true

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

      def resolve(**inputs)
        setting = @context[:viewer].mobile_push_notification_setting || MobilePushNotificationSetting.create(user: @context[:viewer])

        setting.direct_mention = inputs[:get_direct_mentions] unless inputs[:get_direct_mentions].nil?
        setting.assignment = inputs[:get_assignments] unless inputs[:get_assignments].nil?
        setting.review_requested = inputs[:get_review_requests] unless inputs[:get_review_requests].nil?
        setting.deployment_request = inputs[:get_deployment_requests] unless inputs[:get_deployment_requests].nil?
        setting.pull_request_review = inputs[:get_pull_request_reviews] unless inputs[:get_pull_request_reviews].nil?
        setting.scheduled_notifications = inputs[:scheduled_notifications] unless inputs[:scheduled_notifications].nil?
        setting.ci_activity = inputs[:get_ci_activity] unless inputs[:get_ci_activity].nil?
        setting.ci_failed_only = inputs[:get_ci_failed_only] unless inputs[:get_ci_failed_only].nil?
        setting.releases = inputs[:get_releases] unless inputs[:get_releases].nil?

        GitHub.newsies.get_and_update_settings(@context[:viewer]) do |newsies_settings|
          newsies_settings.direct_mention_mobile_push = setting.direct_mention
        end

        if setting.save
          {
            user: @context[:viewer],
            errors: [],
          }
        else
          {
            user: nil,
            errors: Platform::UserErrors.mutation_errors_for_model(setting),
          }
        end
      end
    end
  end
end
