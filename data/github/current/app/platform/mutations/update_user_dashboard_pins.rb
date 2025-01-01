# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateUserDashboardPins < Platform::Mutations::Base
      description "Pin an item to a user's dashboard without modifying other pins."
      minimum_accepted_scopes ["user"]

      mobile_only true

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(:update_user, resource: permission.viewer,
                                   current_repo: nil, current_org: nil,
                                   allow_integrations: false, allow_user_via_granular_actor: false)
      end

      argument :item_ids, [ID], "IDs of the items you want to pin to your dashboard.",
        required: true, loads: Unions::DashboardPinnableItem

      field :user, Objects::User,
        "The owner of the dashboard that was updated.", null: true

      def resolve(items:)
        if items.count > UserDashboardPin::LIMIT_PER_USER_DASHBOARD
          raise Errors::ArgumentLimit.new("You can only pin up to #{UserDashboardPin::LIMIT_PER_USER_DASHBOARD} items.")
        end

        UserDashboardPinner.pin(*items, user: context[:viewer], viewer: context[:viewer])

        { user: context[:viewer] }
      end
    end
  end
end
