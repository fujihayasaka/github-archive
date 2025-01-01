# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class NotificationFilter < Platform::Objects::Base
      extend Helpers::Newsies

      model_name "Newsies::CustomInbox"
      description "Represents a notification filter for the viewer's notifications."
      minimum_accepted_scopes ["notifications"]
      mobile_only true

      implements_node templates: [[:ucnf, :user_id, :notification_filter_id], [:udnf, :user_id, :default_filter_id]], as: "NF", ready_date: Platform::Helpers::GlobalId::COHORT_2, uses_database_id: false do |notification_filter|
        if notification_filter.default_filter?
          {
            prefix: :udnf,
            user_id: notification_filter.user_id,
            default_filter_id: notification_filter.default_filter_id
          }
        else
          {
            prefix: :ucnf,
            user_id: notification_filter.user_id,
            notification_filter_id: notification_filter.id
          }
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      #
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, notification_filter)
        notification_filter.async_target_for_conditional_access.then do |tfca|
          permission.access_allowed?(:show_notification_filter,
            resource: notification_filter,
            tfca: tfca,
            current_repo: nil,
            current_org: nil,
            allow_integrations: false,
            allow_user_via_granular_actor: false,
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      #
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.viewer.id == object.user_id
      end

      def self.load_from_global_id(id)
        unpack_newsies_response!(GitHub.newsies.web.get_custom_inbox(id))
      end

      field :name, String, description: "The user-provided name of the custom inbox", null: false
      field :query_string, String, description: "The query used to filter the inbox.", null: false
      field :unread_count, Integer, method: :async_batch_unread_count, description: "The count of unread notifications in the inbox.", null: false
      field :is_default_filter, Boolean, method: :default_filter?, description: "Returns true if the record is a default filter.", null: false
      created_at_field
      updated_at_field
    end
  end
end
