# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class DashboardPinnedItems < Resolvers::Base
      type Connections.define(Unions::DashboardPinnableItem), null: false

      argument :types, [Enums::PinnableItemType],
        "Filter the types of pinned items that are returned.", required: false

      def resolve(types: UserDashboardPin.pinned_item_types.keys)
        # Object can be a User
        if object.user? && object == context[:viewer]
          excluded_account_ids = @context[:unauthorized_organization_ids] || []
          items = object.dashboard_pinned_items(viewer: context[:viewer], types: types, excluded_account_ids: excluded_account_ids)
          ArrayWrapper.new(items)
        else
          ArrayWrapper.new
        end
      end
    end
  end
end
