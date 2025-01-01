# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetUserDashboardPins < Platform::Mutations::Base
      description "Pin items to a user's dashboard."

      minimum_accepted_scopes ["repo"]

      visibility :under_development

      argument :user_id, ID, "ID of the owner of the dashboard to modify.",
        required: true, loads: Objects::User
      argument :pinned_item_ids, [ID], "IDs of the pinned items in the order you want them to appear on your user dashboard. Will replace all dashboard pins with those specified.",
        required: true, loads: Unions::DashboardPinnableItem

      field :user, Objects::User,
        "The owner of the dashboard that was updated.", null: true

      def resolve(user:, pinned_items:)
        unless user.can_pin_dashboard_items?(context[:viewer])
          error_message = "#{context[:viewer].display_login} cannot pin items on #{user.display_login}'s dashboard"
          raise Errors::Forbidden.new(error_message)
        end

        pinner = UserDashboardPinner.pin(*pinned_items, user: user, viewer: context[:viewer])

        { user: user }
      end
    end
  end
end
