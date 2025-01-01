# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    # TODO rename this to `ExploreCollectionItem` to match `ExploreCollection`
    class CollectionItem < Platform::Objects::Base
      description "A CollectionItem is a Repository, User, Organization or other interesting links."

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
        permission.belongs_to_collection(object)
      end

      scopeless_tokens_as_minimum

      visibility :internal

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      global_id_field :id, description: "The Node ID of the CollectionItem object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      field :slug, String, "The collection item's slug name.", null: false
      field :content_type, String, "The type of the content item.", null: false
      field :content, Unions::CollectionItemContent, description: "The collection item content.", null: true

      def content
        klass = @object.content_type.classify.constantize

        Platform::Loaders::ActiveRecord.load(klass, @object.content_id).then do |content|
          if "User".eql?(@object.content_type) && content.organization?
            Platform::Loaders::ActiveRecord.load(::Organization, @object.content_id)
          else
            content
          end
        end
      end
    end
  end
end
