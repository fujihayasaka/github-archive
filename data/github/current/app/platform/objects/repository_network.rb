# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    # Note - RepositoryNetwork has a temp Ability check, fix that before giving this a gloabl ID.
    class RepositoryNetwork < Platform::Objects::Base
      description "A repository network."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, obj)
        permission.hidden_from_public?(self) # Update this authorization if we ever go public with this object
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # TODO: If we ever give RepositoryNetwork an id, we need to properly implement this ability check.
      # You should only be able to access the object if you can read at least 1 repository on the network.
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      minimum_accepted_scopes ["public_repo"]
      visibility :internal

      field :root, Repository, method: :async_root, description: "The root repository of the network.", null: true

      field :repositories, resolver: Resolvers::Repositories, description: "A list of repositories in the network.", connection: true
    end
  end
end
