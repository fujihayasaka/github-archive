# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ReorderDashboardPins < Platform::Mutations::Base
      description "Reorder the items pinned to the specified user's dashboard."

      minimum_accepted_scopes ["repo"]

      visibility :under_development

      argument :user_id, ID, "ID of the owner of the dashboard to modify.",
        required: true, loads: Objects::User
      argument :pinned_item_ids, [ID], "IDs of the pinned items in the order you want them to appear on your user dashboard.", required: true, loads: Unions::DashboardPinnableItem

      field :user, Objects::User,
        "The owner of the dashboard that was updated.", null: true

      def resolve(user:, pinned_items:)
        unless user.can_pin_dashboard_items?(context[:viewer])
          error_message = "#{context[:viewer].display_login} cannot reorder pins on #{user.display_login}'s dashboard"
          raise Errors::Forbidden.new(error_message)
        end

        user.reorder_dashboard_pinned_items(pinned_items)

        { user: user }
      end
    end
  end
end
