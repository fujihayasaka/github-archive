# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CollectionVideo < Platform::Objects::Base
      description "A type of collection item comprised of a Video."

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

      global_id_field :id, description: "The Node ID of the CollectionVideo object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      field :url, Scalars::URI, "The collection video's URL.", null: false
      field :thumbnail_url, Scalars::URI, "The collection video's thumbnail URL.", null: true
      field :title, String, "The collection video's title.", null: false
      field :description, String, "The collection video's description.", null: false
    end
  end
end
