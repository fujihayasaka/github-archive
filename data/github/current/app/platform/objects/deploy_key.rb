# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DeployKey < Platform::Objects::Base
      model_name "PublicKey"
      description "A repository deploy key."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, key)
        permission.typed_can_access?("PublicKey", key)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_repository.then do |repo|
          permission.typed_can_see?("Repository", repo)
        end
      end

      minimum_accepted_scopes ["public_repo"]

      # DeployKey is migrated over to the new global ID format as a by-product of it's backing model - PublicKey.
      # There is another Platform::Object:: called PublicKey which has it's default model as the Rails PublicKey class.
      # It will choose that object to return from in the id_from_object method.
      # Thus, it's existing globalID implementation remains
      allow_legacy_global_id_implementation
      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject
      global_id_field :id, description: "The Node ID of the DeployKey object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      field :key, String, "The deploy key.", null: false
      field :title, String, "The deploy key title.", null: false
      field :verified, Boolean, "Whether or not the deploy key has been verified.", method: :verified?, null: false
      field :read_only, Boolean, "Whether or not the deploy key is read only.", method: :read_only?, null: false
      created_at_field
    end
  end
end
