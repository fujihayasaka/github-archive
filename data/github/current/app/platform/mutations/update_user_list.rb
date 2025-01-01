# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateUserList < Platform::Mutations::Base
      description "Updates an existing user list."
      minimum_accepted_scopes ["user"]
      extras [:execution_errors]

      argument :list_id, ID, "The ID of the list to update.", required: true, loads: Objects::UserList, as: :list
      argument :name, String, "The name of the list", required: false
      argument :description, String, "A description of the list", required: false
      argument :is_private, Boolean, "Whether or not the list is private", required: false

      field :list, Objects::UserList, "The list that was just updated", null: true
      error_fields

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(
          :update_user,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false)
      end

      def resolve(list:, execution_errors:, **inputs)
        if !context[:viewer].can_modify_list?(list)
          raise Errors::NotFound.new("List not found #{list.global_relay_id}")
        end

        name = inputs[:name] || list.name
        description = inputs[:description] || list.description

        # A list will remain private if it's currently private and no value
        # is passed for isPrivate. Otherwise we default to the argument value.
        is_private = inputs[:is_private]
        is_private = list.private? if is_private.nil?

        old_list = list.dup.tap { |ul| ul.id = list.id }

        if list.update(name: name, description: description, private: is_private)
          list.instrument_hydro_update(old_list: old_list)

          {
            list: list,
            errors: []
          }
        else
          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(list, execution_errors)

          {
            list: list,
            errors: Platform::UserErrors.mutation_errors_for_model(list)
          }
        end

      end
    end
  end
end
