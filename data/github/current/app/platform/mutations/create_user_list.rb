# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateUserList < Platform::Mutations::Base
      description "Creates a new user list."
      minimum_accepted_scopes ["user"]
      extras [:execution_errors]

      argument :name, String, "The name of the new list", required: true
      argument :description, String, "A description of the list", required: false
      argument :is_private, Boolean, "Whether or not the list is private", required: false, default_value: false

      field :list, Objects::UserList, "The list that was just created", null: true
      field :viewer, Objects::User, "The user who created the list", null: true
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

      def resolve(name:, execution_errors:, **inputs)
        list = context[:viewer].lists.build(
          name: name,
          description: inputs[:description],
          private: inputs[:is_private] || false,
        )

        if list.save
          {
            list: list,
            viewer: context[:viewer],
            errors: []
          }
        else
          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(list, execution_errors)

          {
            list: nil,
            viewer: context[:viewer],
            errors: Platform::UserErrors.mutation_errors_for_model(list)
          }
        end
      end
    end
  end
end
