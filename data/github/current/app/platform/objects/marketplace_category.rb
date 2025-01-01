# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MarketplaceCategory < Platform::Objects::Base
      model_name "Marketplace::Category"
      description "A public description of a Marketplace category."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, marketplace_category)
        # Use `true` here because it's public on dotcom, even though it's private on enterprise.
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for a Marketplace::Category object
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      implements_node templates: [[:mc, :marketplace_category_id]], as: "MC", ready_date: Platform::Helpers::GlobalId::COHORT_2 do |marketplace_category|
        {
          prefix: :mc,
          marketplace_category_id: marketplace_category.id,
        }
      end

      minimum_accepted_scopes ["repo"]

      field :name, String, "The category's name.", null: false
      field :slug, String, "The short name of the category used in its URL.", null: false
      field :description, String, "The category's description.", null: true
      field :description_html, Scalars::HTML, "The category's description rendered to HTML.", null: false, visibility: :under_development
      def description_html
        markdown = CommonMarker.render_html(@object.description || "", [:UNSAFE, :GITHUB_PRE_LANG], %i[tagfilter table strikethrough autolink])
        GitHub::Goomba::SimplePipeline.to_html(markdown)
      end

      field :how_it_works, String, "The technical description of how apps listed in this category work with GitHub.", null: true
      field :primary_listing_count, Integer, "How many Marketplace listings have this as their primary category.", null: false
      field :secondary_listing_count, Integer, "How many Marketplace listings have this as their secondary category.", null: false
      field :is_filter, Boolean, "Whether the category is a filter-type.", method: :acts_as_filter?, null: false, visibility: :internal
      field :is_navigation_visible, Boolean, "Whether the category is to be used in Marketplace navigation menus.", method: :navigation_visible?, null: false, visibility: :internal
      field :is_featured, Boolean, "Whether the category is featured in the Marketplace homepage.", method: :featured?, null: false, visibility: :internal
      field :featured_position, Integer, "The position of the category on the Marketplace homepage.", null: true, visibility: :internal
      field :parent_category, Objects::MarketplaceCategory, "The category's parent category.", method: :async_parent_category, null: true, visibility: :under_development
      field :sub_categories, [Objects::MarketplaceCategory], "A list of the category's sub categories.", null: false, visibility: :under_development do
        T.bind(self, GraphQL::Schema::Member::HasArguments)
        argument :for_navigation, Boolean, "Whether or not these categories will be used for Marketplace navigation menus.", required: false, default_value: false
        argument :limit, Integer, "The number of categories to include.", required: false, default_value: Marketplace::Category::SUBCATEGORIES_LIMIT
      end

      def sub_categories(for_navigation:, limit:)
        @object.async_filtered_subcategories(for_navigation: for_navigation, limit: limit)
      end

      url_fields description: "The HTTP URL for this Marketplace category." do |category|
        template = Addressable::Template.new("/marketplace/category/{slug}")
        template.expand slug: category.slug
      end

      field :apps, Connections::MarketplaceListing, visibility: :internal, description: "The (app) listings that belong to this category", null: true, connection: true

      def apps
        @object.listings.publicly_listed
      end

      field :actions, Connections.define(Objects::RepositoryAction), visibility: :internal, description: "The repository actions that belong to this category", null: true, connection: true

      def actions
        @object.actions.with_state(:listed)
      end

      field :featured_actions, Connections.define(Objects::RepositoryAction), visibility: :internal, description: "The featured repository actions that belong to this category", null: true, connection: true

      def featured_actions
        actions.featured
      end
    end
  end
end
