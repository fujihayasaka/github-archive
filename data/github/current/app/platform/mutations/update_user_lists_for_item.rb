# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateUserListsForItem < Platform::Mutations::Base
      description "Updates which of the viewer's lists an item belongs to"

      minimum_accepted_scopes ["user"]

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(:update_user, resource: permission.viewer,
                                   current_repo: nil, current_org: nil,
                                   allow_integrations: false, allow_user_via_granular_actor: false)
      end

      argument :itemId, ID, "The item to add to the list", required: true, loads: Unions::UserListItems, as: :item
      argument :listIds, [ID], "The lists to which this item should belong", required: true, loads: Objects::UserList, as: :lists
      argument :suggestedListIds, [ID], "The suggested lists to create and add this item to", required: false, loads: Objects::UserListSuggestion, as: :suggested_lists

      field :item, Unions::UserListItems, "The item that was added", null: true
      field :lists, [Objects::UserList], "The lists to which this item belongs", null: true
      field :user, Objects::User, "The user who owns the lists", null: true

      def resolve(item:, lists:, suggested_lists: [])
        if lists.any? { |list| list.user != context[:viewer] }
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to manage one or more lists")
        end

        suggested_lists.each do |suggestion|
          list = context[:viewer].lists.build(name: suggestion.name, description: nil, private: false)

          unless list.save
            raise Platform::Errors::ArgumentError.new("Failed to create list: #{list.errors.full_messages.join(", ")}")
          end

          lists << list
        end

        UserList.replace_all(
          user_id: context[:viewer].id,
          repository_id: item.id,
          list_ids: lists.map(&:id)
        )

        { item: item, lists: lists, user: context[:viewer] }
      end
    end
  end
end
