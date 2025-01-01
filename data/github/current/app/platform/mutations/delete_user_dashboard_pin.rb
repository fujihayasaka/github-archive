# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteUserDashboardPin < Platform::Mutations::Base
      description "Unpin an item from a user's dashboard without modifying other pins."
      minimum_accepted_scopes ["user"]

      required_capabilities [:mobile_only_schema_mask]

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(:update_user, resource: permission.viewer,
                                   current_repo: nil, current_org: nil,
                                   allow_integrations: false, allow_user_via_granular_actor: false)
      end

      argument :user_id, ID, "ID of the owner of the dashboard to modify.",
        required: false
      argument :item_id, ID, "ID of the item you want to unpin from a user's dashboard.",
        required: true, loads: Unions::DashboardPinnableItem

      field :user, Objects::User,
        "The owner of the dashboard that was updated.", null: true

      def resolve(item:, **inputs)
        result = context[:viewer].unpin_item_from_dashboard(item)

        if result || result.nil?
          { user: context[:viewer] }
        else
          raise Errors::Unprocessable.new("Could not unpin item from #{context[:viewer].display_login}'s dashboard")
        end
      end
    end
  end
end
