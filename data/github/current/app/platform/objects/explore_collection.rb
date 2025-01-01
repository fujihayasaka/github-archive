# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class ExploreCollection < Platform::Objects::Base
      description "An Explore Collection aggregates interesting content related to a subject."

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

      global_id_field :id, description: "The Node ID of the ExploreCollection object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      database_id_field(visibility: :internal)
      field :author, String, "The collection's author.", null: true
      field :description, String, "A brief description of what the collection is about.", null: false
      field :display_name, String, "The collection's name.", null: true
      field :image_url, Scalars::URI, "Returns the URL for an image representing this collection.", null: true
      field :is_featured, Boolean, "Whether this collection is featured on GitHub.", method: :featured?, null: false
      field :is_published, Boolean, "Whether or not this collection is published on GitHub.", method: :published?, null: false
      field :slug, String, "The collection's short URL name.", null: false
      field :short_description_html, Scalars::HTML, description: "A description of the collection description, rendered to HTML without any links in it.", null: false do
        argument :limit, Integer, "How many characters to return.", default_value: 200, required: false
      end

      def short_description_html(**arguments)
        @object.async_short_description_html(limit: arguments[:limit])
      end

      url_fields description: "The HTTP URL for this collection.", visibility: :internal do |collection, _arguments, _context|
        template = "/collections/{collection}"

        Addressable::Template.new(template).expand(collection: collection.slug)
      end

      field :items, Connections.define(Objects::CollectionItem), visibility: :internal, description: "Returns a list of the collection items.", null: false, connection: true

      def items
        ArrayWrapper.new(::CollectionItem.where(collection_id: @object.id).visible)
      end

      def self.load_from_global_id(slug)
        Loaders::ActiveRecord.load(::ExploreCollection, slug, column: :slug)
      end
    end
  end
end
