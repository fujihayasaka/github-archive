# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteUserList < Platform::Mutations::Base
      description "Deletes a user list."
      minimum_accepted_scopes ["user"]

      argument :list_id, ID, "The ID of the list to delete.", required: true, loads: Objects::UserList

      field :user, Objects::User, "The owner of the list that will be deleted", null: true

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(
          :update_user,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false)
      end

      def resolve(list:)
        if !context[:viewer].can_modify_list?(list)
          raise Errors::NotFound.new("Could not find list #{list.global_relay_id}")
        end

        list.destroy!

        { user: context[:viewer] }
      end
    end
  end
end
