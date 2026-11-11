# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class UserListSuggestion < Platform::Objects::Base
      description "Represents a suggested user list."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(_permission, _object)
        # See Platform::Platform::UpdateUserListsForItem#resolve or Platform::Objects::User#suggested_list_names
        # Only used to create new list suggestions on the mutation or viewing predefined list suggestions on the user
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(_permission, _object)
        # See Platform::Platform::UpdateUserListsForItem#resolve or Platform::Objects::User#suggested_list_names
        # Only used to create new list suggestions on the mutation or viewing predefined list suggestions on the user
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :name, String, "The name of the suggested user list", null: true
      field :id, ID, "The ID of the suggested user list", null: true

      def self.load_from_global_id(id)
        Models::UserListSuggestion.load_from_global_id(id)
      end

      def id
        Models::UserListSuggestion.to_global_id(name: object.name)
      end
    end
  end
end
