# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class NotificationThread < Platform::Objects::Base
      extend Helpers::Newsies
      extend Helpers::ConditionalAccess

      description "Represents a notification thread for the viewer."
      required_capabilities [:mobile_only_schema_mask, :access_internal_graphql_notifications]
      minimum_accepted_scopes ["notifications"]

      implements_node templates: [[:unt, :user_id, :notification_thread_id]], as: "NT", ready_date: Platform::Helpers::GlobalId::COHORT_5 do |notification_thread|
        {
          prefix: :unt,
          user_id: notification_thread.user.id,
          notification_thread_id: notification_thread.id
        }
      end

      # Checks the given `action` for the notification thread with the correct context applied
      def self.access_allowed?(permission, object, action)
        object.async_list.then do |list|
          next false unless list.present?
          promises = [list.try(:async_owner) || list.try(:async_organization)]
          if list.is_a?(::Repository)
            promises << list.async_ip_restricted_private_fork?
          end
          Promise.all(promises).then do |owner, ip_restricted_private_fork|
            current_org = if owner.present? && owner.organization?
              owner
            end
            object.async_target_for_conditional_access.then do |tfca|
              permission.access_allowed?(
                action,
                resource: object,
                current_repo: list.is_a?(::Repository) ? list : nil,
                ip_restricted_private_fork: ip_restricted_private_fork,
                current_org: current_org,
                tfca: tfca,
                allow_integrations: false,
                allow_user_via_granular_actor: false,
                allow_mutation_on_public_resource: true
              )
            end
          end
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        access_allowed?(permission, object, :show_notification_thread)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        unauthorized_account_ids = unauthorized_account_ids(permission.viewer, permission.cap_filter)
        object.async_readable_by?(permission.viewer, unauthorized_account_ids: unauthorized_account_ids)
      end

      def self.load_from_next_global_id(parsed_id)
        load_from_global_id(parsed_id.parts[:notification_thread_id])
      end

      # Loads the NotificationThread model
      def self.load_from_global_id(id)
        summary_id, user_id = id.split(":")

        Platform::Loaders::ActiveRecord.load(::User, user_id.to_i).then do |user|
          next unless user

          # It's possible that a user has a saved notification but the original notification entry has been
          # deleted. In that case we will fall back to using the summary hash from the saved notification entry
          notification = unpack_newsies_response!(GitHub.newsies.web.summary_hash_from_summary_id(user, summary_id))
          saved_notification = unpack_newsies_response!(GitHub.newsies.web.saved_summary_hash_from_summary_id(user, summary_id))

          summary_hash = notification || saved_notification
          next unless summary_hash.present?

          Platform::Models::NotificationThread.new(summary_hash, user: user, starred: saved_notification.present?)
        end
      end



      field :url,
        Platform::Scalars::URI,
        description: "The HTTP URL for the notification thread's subject",
        method: :async_url,
        null: false

      field :summary_id,
        String,
        description: "The notification's rollup summary id",
        null: false

      field :list_type,
        String,
        description: "The notification's list type",
        null: false

      field :list_id,
        String,
        description: "The notification's list id",
        null: false

      field :thread_type,
        String,
        description: "The notification's thread type",
        null: false

      field :thread_id,
        String,
        description: "The notification's thread id",
        null: false

      field :last_comment_type,
        String,
        description: "The last comment's type",
        null: false,
        visibility: :internal

      field :last_comment_id,
        String,
        description: "The last comment's id",
        null: false,
        visibility: :internal

      field :title,
        String,
        description: "The notification's title",
        null: false

      field :is_unread,
        Boolean,
        description: "Unread state of the notification.",
        null: false,
        method: :unread?

      field :is_archived,
        Boolean,
        description: "Archived state of the notification.",
        null: false,
        method: :archived?

      field :is_done,
        Boolean,
        description: "Done state of the notification.",
        null: false,
        method: :archived?

      field :last_read_at,
        Scalars::DateTime,
        description: "The last time that notifications were read for this thread.",
        null: true

      field :last_summarized_at,
        Scalars::DateTime,
        description: "The last time that notifications were updated for this thread.",
        null: false

      field :last_updated_at,
        Scalars::DateTime,
        description: "The last time that a notification was received on this thread for the current user",
        null: false

      field :reason,
        Enums::NotificationReason,
        description: "The reason a notification was received.",
        null: true

      field :list,
        Unions::NotificationsList,
        description: "The notification's list.",
        null: false,
        method: :async_list

      field :subject,
        Unions::NotificationsSubject,
        description: "The notification's subject.",
        null: false,
        method: :async_subject

      field :recent_participants,
        [User],
        description: "The last 3 recent participants.",
        null: false,
        method: :async_recent_participants

      field :summary_item_author,
        User,
        description: "The author of the item being used to summarize the thread.",
        null: true

      field :summary_item_body,
        String,
        description: "The body text of the item being used to summarize the thread.",
        null: true

      field :check_suite_summary_conclusion,
        String,
        description: "When the subject is a CheckSuite, the conclusion of that CheckSuite.",
        visibility: :internal,
        null: true

      field :unread_items_count,
        Integer,
        description: "The number of unread items.",
        null: false

      field :is_starred,
        Boolean,
        description: "Whether a notification has been starred",
        null: false,
        method: :starred?

      field :is_saved,
        Boolean,
        description: "Whether a notification has been saved",
        null: false,
        method: :starred?

      field :subscription_status,
        Enums::NotificationThreadSubscriptionState,
        description: "Subscription status for the thread",
        null: false,
        method: :async_subscription_status

      field :oldest_unread_item_anchor,
        String,
        description: "The oldest unread author internal anchor",
        null: true

      field :subscription_type,
        String,
        description: "What is the thread subscription type for this notification?",
        null: false,
        method: :async_subscription_type,
        visibility: :internal
    end
  end
end
