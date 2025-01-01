# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateNotificationViewPreference < Platform::Mutations::Base
      include Helpers::Newsies

      description "Updates the user's notification view preference"
      visibility :internal
      minimum_accepted_scopes ["user"]
      required_capabilities [:access_internal_graphql_notifications]

      argument :view_preference, String, "The user's notification view preference, either 'group_by_repository' or 'sort_by_date'", required: true

      field :success, Boolean, "Did the operation succeed?", null: true
      field :viewer, Objects::User, "The user whose preferences were updated.", null: true
      error_fields

      def self.async_api_can_modify?(permission, **inputs)
        permission.can_list_user_notifications?(permission.viewer)
      end

      def resolve(view_preference:)
        viewer = context[:viewer]
        errors = []

        if view_preference == "group_by_repository"
          viewer.set_prefers_notifications_group_by_list_view
        elsif view_preference == "sort_by_date"
          viewer.unset_prefers_notifications_group_by_list_view
        else
          raise Platform::Errors::ArgumentError, "viewPreference must be either 'group_by_repository' or 'sort_by_date'"
        end

        {
          success: true,
          viewer: context[:viewer],
          errors: [],
        }
      end
    end
  end
end
