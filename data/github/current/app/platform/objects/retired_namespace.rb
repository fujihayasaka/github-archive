# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RetiredNamespace < Platform::Objects::Base
      description "A namespace that is no longer available to new repositories"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.viewer.site_admin?
      end

      visibility :internal
      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject
      global_id_field :id, description: "The Node ID of the RetiredNamespace object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      minimum_accepted_scopes ["site_admin"]

      field :owner_login, String, description: "The owning user or organization's login", null: false
      field :name, String, description: "The retired repository name", null: false
      field :owner, Interfaces::RepositoryOwner, method: :async_owner,
        description: "The owning user or organization. May be null if the account was removed.", null: true
      field :name_with_owner, String, "The repository name with owner", null: false
      created_at_field(null: false)
    end
  end
end
