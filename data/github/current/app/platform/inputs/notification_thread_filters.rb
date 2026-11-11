# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class NotificationThreadFilters < Platform::Inputs::Base
      description "Ways in which to filter lists of notification threads."
      required_capabilities [:mobile_only_schema_mask, :access_internal_graphql_notifications]

      argument :statuses, [Platform::Enums::NotificationStatus], "Only return notifications where the status is in the list.", required: false
      argument :reasons, [Platform::Enums::NotificationReason], "Only return notification threads where the reason is in the list", required: false
      argument :list_ids, [ID], "Only return notification threads where the list is in the given list", required: false
      argument :starred_only, Boolean, "Only return starred notifications. All other filters will be ignored.", required: false, default_value: false
      argument :saved_only, Boolean, "Only return saved notifications. All other filters will be ignored.", required: false, default_value: false
      argument :thread_types, [String], "Only return matching thread types", required: false
    end
  end
end
