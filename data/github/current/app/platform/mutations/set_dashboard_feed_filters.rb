# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetDashboardFeedFilters < Platform::Mutations::Base
      description "Set the filters for a user's dashboard feed"
      minimum_accepted_scopes ["user"]
      mobile_only true

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(
          :update_user,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false
        )
      end

      argument :filter_groups, [Enums::DashboardFeedFilterGroup], "Filter groups that are enabled", required: true

      field :filters, [Objects::Conduit::FeedFilter], "The filter settings for this feed", null: true

      def resolve(filter_groups:)
        user = context[:viewer]
        excluded_all_filter = ::Conduit::FeedFilter::exclude_all_filter
        filter = ::Conduit::FeedFilter.new(excluded_all_filter, viewer: user)

        updated_filter = filter.with_groups(filter_groups)
        user.set_for_you_feed_filter!(updated_filter)

        new_filter = ::Conduit::FeedFilter.new(updated_filter, viewer: user)
        groups = ::Conduit::FeedFilter.available_groups(viewer: user)
        filters = groups.map do |name, _|
          Models::Conduit::FeedFilter.new(
            name: name,
            is_enabled: new_filter.includes_group?(name),
            user: user
          )
        end

        { filters: filters }
      end
    end
  end
end
