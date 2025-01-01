# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Conduit::FeedFilter < Platform::Objects::Base
      description "A single content filter for an event feed"
      minimum_accepted_scopes ["read:user"]
      mobile_only true

      def self.async_api_can_access?(permission, object)
        permission.viewer == object.user
      end

      def self.async_viewer_can_see?(permission, object)
        permission.viewer == object.user
      end

      field :name, String, "The name of the filter", null: false

      field :is_enabled, Boolean, "Whether or not the filter is enabled", null: false

      field :filter_group, Enums::DashboardFeedFilterGroup, "The filter group that this filter belongs to", null: false
    end
  end
end
