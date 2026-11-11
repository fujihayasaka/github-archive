# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CollectionUrl < Platform::Objects::Base
      description "A type of collection item comprised of a URL."

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
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      visibility :internal

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      global_id_field :id, description: "The Node ID of the CollectionUrl object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      field :url, Scalars::URI, "The collection URL's URL.", null: false
      field :title, String, "The collection URL's title.", null: false
      field :description, String, "The collection URL's description.", null: false
    end
  end
end
