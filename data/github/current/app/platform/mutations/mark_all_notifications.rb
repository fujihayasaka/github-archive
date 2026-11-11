# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MarkAllNotifications < Platform::Mutations::Base
      extend Helpers::Newsies

      description "Mark all notifications as the state is passed"
      required_capabilities [:mobile_only_schema_mask, :access_internal_graphql_notifications]
      minimum_accepted_scopes ["notifications"]

      argument :query, String, "Filter used to mark all specific notifications.", required: true
      argument :state, Enums::NotificationStatus, "The new state for the notification.", required: true
      field :success, Boolean, "Did the operation succeed?", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # This function uses a simplified permissions check as it avoids duplicate efforts while checking for viewer access.
      def self.async_api_can_modify?(permission, **inputs)
        permission.can_list_user_notifications?(permission.viewer)
      end

      def resolve(**inputs)
        # We only allow to run one mark_all_from_query job at a time.
        # If there is an existing job running, return an error
        status = Newsies::MarkAllNotificationsFromQueryJobStatus.status(@context[:viewer].id)

        if status && !status.finished?
          raise Errors::ArgumentLimit.new("There is a current mark all notifications job running.")
        end

        new_state = inputs[:state].gsub("inbox_", "").to_sym
        unless GitHub.newsies.web.mark_all_from_query(@context[:viewer], new_state, filter_options(inputs[:query])).success?
          return {
            success: false,
          }
        end
        {
          success: true,
        }
      end

      def filter_options(query)
        parsed_query = Search::Queries::NotificationsQuery.new(query: query, viewer: @context[:viewer])

        {
          thread_types: nil,
          before: Time.now.utc,
          lists: parsed_query.qualifier_used?(:repo) ? parsed_query.repositories.map(&:global_relay_id) : nil,
          owners: nil,
          authors: nil,
          reasons: nil,
          statuses: [:unread, :read]
        }.compact
      end
    end
  end
end
