# typed: false # rubocop:disable Sorbet/TrueSigil
# frozen_string_literal: true

module Platform::Objects::Query::Marketplace
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  included do
    field :marketplace_search, Connections::SearchResultItem,
      map_to_service: :marketplace,
      visibility:     :internal,
      description:    "Search GitHub Marketplace.",
      null:           false,
      connection:     true do
      argument :query, String, "Select listings that match this text.", required: true
      argument :category_slug, String, "Search listings within the category with this slug.", required: false
      argument :enterprise_compatible_only, Boolean, "Include only listings that are compatible with GitHub Enterprise.", required: false
      argument :type, Enums::MarketplaceSearchType, <<~DESCRIPTION, required: false
        What kind of search results to return.
      DESCRIPTION
      argument :with_free_trials_only, Boolean, "Select only listings that offer a free trial.", required: false
      argument :verification_state, Enums::MarketplaceVerificationState, "Select the listings in this verification state that are visible to the viewer.", required: false
    end

    def marketplace_search(query:, category_slug: nil, enterprise_compatible_only: nil, type: nil, with_free_trials_only: nil, verification_state: nil)
      promise = if category_slug.present?
        Loaders::ActiveRecord.load(::Marketplace::Category, category_slug, column: :slug).then do |mkt_category|
          Loaders::ActiveRecord.load(::IntegrationFeature, category_slug, column: :slug).then do |wwg_category|
            query += %Q( category:"#{wwg_category.name}") if wwg_category

            if mkt_category
              query += %Q( category:"#{mkt_category.name}" )

              # nb: here we query for sub categories so that when looking at a
              # parent category we also include the items tied to sub
              # categories
              mkt_category.async_sub_categories.then do |sub_categories|
                sub_categories.each { |sub_category| query += %Q( category:"#{sub_category.name}" ) }
              end
            end
          end
        end
      else
        Promise.resolve(true)
      end

      case verification_state
      when "verified"
        query += %Q( state:verified )
      when "unverified"
        query += %Q( state:unverified state:verification_pending_from_unverified state:verified_creator)
      end

      promise.then do
        Search::Queries::MarketplaceQuery.new \
          current_user: @context[:viewer],
          phrase: query,
          type: type,
          offers_free_trial: with_free_trials_only,
          enterprise_compatible: enterprise_compatible_only,
          verification_state: verification_state,
          context: "graphql-marketplace-search",
          highlight: ::Search::OffsetHighlighter.defaults
      end
    end

    field :marketplace_category, Objects::MarketplaceCategory,
      map_to_service: :marketplace,
      description:    "Look up a Marketplace category by its slug.",
      null:           true do
      argument :slug, String, "The URL slug of the category.", required: true
      argument :use_topic_aliases, Boolean, "Also check topic aliases for the category slug", required: false
    end

    def marketplace_category(**arguments)
      slug = arguments[:slug]

      return unless slug.present?

      if arguments[:use_topic_aliases]
        aliased_slug = ::Marketplace::Category.slug_for_topic(slug)
      end

      Loaders::ActiveRecord.load(::Marketplace::Category, aliased_slug || slug, column: :slug)
    end

    field :marketplace_categories, [Objects::MarketplaceCategory],
      map_to_service: :marketplace,
      description:    "Get alphabetically sorted list of Marketplace categories",
      null:           false do
      argument :include_categories, [String], "Return only the specified categories.", required: false
      argument :exclude_empty, Boolean, "Exclude categories with no listings.", required: false
      argument :exclude_subcategories, Boolean, "Returns top level categories only, excluding any subcategories.", required: false
      argument :exclude_filter_categories, Boolean, "Exclude filter-type categories.", required: false, default_value: false, visibility: :under_development
      argument :subcategory_candidates_for, String, "Return categories that can be used as subcategories for the given category slug.", required: false, visibility: :internal
      argument :for_navigation, Boolean, "Only return categories that are visible in side navigation and have listings.", visibility: :internal, required: false, default_value: false
    end

    def marketplace_categories(**arguments)
      categories = ::Marketplace::Category.order(:name)
      categories = categories.not_sponsors_only
      categories = categories.where(slug: arguments[:include_categories]) if arguments[:include_categories]
      categories = categories.with_listings if arguments[:exclude_empty]
      categories = categories.top_level if arguments[:exclude_subcategories]
      categories = categories.where(acts_as_filter: false) if arguments[:exclude_filter_categories]
      categories = categories.subcategory_candidates(for_optional_slug: arguments[:subcategory_candidates_for]) if arguments.key?(:subcategory_candidates_for)
      categories = categories.navigation_visible.with_listings if arguments[:for_navigation]
      categories
    end

    field :featured_marketplace_categories, [Objects::MarketplaceCategory],
      map_to_service: :marketplace,
      description:    "A list of categories that are featured on the Marketplace homepage",
      null:           false,
      visibility:     :internal

    def featured_marketplace_categories
      ::Marketplace::Category.featured
    end

    field :marketplace_purchase, Objects::SubscriptionItem,
      map_to_service: :marketplace,
      visibility:     :internal,
      description:    "Get subscription details for an account's purchase of a Marketplace listing.",
      null:           true do
      argument :account_id, Integer, "The database ID of the User or Organization account.", required: true
      argument :marketplace_listing_id, Integer, "The database ID of the Marketplace listing.", required: true
    end

    def marketplace_purchase(account_id:, marketplace_listing_id:)
      Loaders::ActiveRecord.load(::User, account_id, column: :id).then do |user|
        user.async_business.then do |business|
          account = business&.self_serve_payment? ? business : user
          account.async_customer.then do |_customer|
            account.async_plan_subscription.then do |plan_subscription|
              listing_plans_ids = ::Marketplace::ListingPlan.where(
                marketplace_listing_id: marketplace_listing_id,
              ).pluck(:id)
              if plan_subscription
                query = plan_subscription.active_subscription_items.for_marketplace_listing_plans(listing_plans_ids)
                plan_subscription.async_billable_entity.then do |owner|
                  if owner.business?
                    query.for_organization(user)&.first
                  else
                    query&.first
                  end
                end
              else
                nil
              end
            end
          end
        end
      end
    end

    field :marketplace_listing, Objects::MarketplaceListing,
      description: "Look up a single Marketplace listing", null: true, map_to_service: :marketplace do
      argument :slug, String, "Select the listing that matches this slug. It's the short name of the listing used in its URL.", required: true
    end

    def marketplace_listing(**arguments)
      promise = Loaders::ActiveRecord.load(::Marketplace::Listing, arguments[:slug], column: :slug)
      promise.then do |listing|
        if listing
          listing.async_owner.then do
            @context[:permission].typed_can_see?("MarketplaceListing", listing).then do |listing_readable|
              if listing_readable
                if listing.listable_is_integration?
                  @context[:permission].typed_can_see?("App", listing.integratable).then do |app_readable|
                    listing if app_readable
                  end
                else
                  listing
                end
              end
            end
          end
        end
      end
    end

    field :marketplace_listings, Connections::MarketplaceListing,
      map_to_service: :marketplace,
      description:    "Look up Marketplace listings",
      null:           false,
      connection:     true do
      argument :category_slug, String, "Select only listings with the given category.", required: false
      argument :use_topic_aliases, Boolean, "Also check topic aliases for the category slug", required: false
      argument :query, String, "Select listings whose name or description matches the query.", visibility: :internal, required: false
      argument :viewer_can_admin, Boolean, <<~DESCRIPTION, required: false
          Select listings to which user has admin access. If omitted, listings visible to the
          viewer are returned.
        DESCRIPTION
      argument :admin_id, ID, "Select listings that can be administered by the specified user.", required: false
      argument :organization_id, ID, "Select listings for products owned by the specified organization.", required: false
      argument :all_states, Boolean, <<~DESCRIPTION, required: false
          Select listings visible to the viewer even if they are not approved. If omitted or
          false, only approved listings will be returned.
        DESCRIPTION
      argument :state, Enums::MarketplaceListingState, "Select the listings in this state that are visible to the viewer.", required: false
      argument :states, [Enums::MarketplaceListingState], "Select the listings in these states that are visible to the viewer.", required: false, visibility: :under_development
      argument :slugs, [String, null: true], "Select the listings with these slugs, if they are visible to the viewer.", required: false
      argument :primary_category_only, Boolean, "Select only listings where the primary category matches the given category slug.", default_value: false, required: false
      argument :with_free_trials_only, Boolean, "Select only listings that offer a free trial.", default_value: false, required: false
      argument :featured_only, Boolean, "Select only listings that are currently featured.", default_value: false, visibility: :internal, required: false
      argument :order_by, Inputs::MarketplaceListingOrder, "Ordering options for the returned listings.", required: false, default_value: { field: "id", direction: "DESC" }
    end

    def marketplace_listings(**arguments)
      viewer = @context[:viewer]

      listings = ::Marketplace::Listing.scoped

      if arguments[:order_by].present?
        field = arguments[:order_by][:field]
        direction = arguments[:order_by][:direction]
        listings = listings.unscope(:order).order("#{field} #{direction}")
      end

      if arguments[:with_free_trials_only]
        listings = listings.with_free_trial(state: :published)
      end

      if arguments[:featured_only]
        listings = listings.featured
      end

      if (slug = arguments[:category_slug]).present?
        if arguments[:use_topic_aliases]
          aliased_slug = Marketplace::Category.slug_for_topic(slug)
        end

        listings = listings.with_category(aliased_slug || slug, primary_category_only: arguments[:primary_category_only])
      end

      if (query = arguments[:query]).present?
        listings = listings.matches_name_or_description(query)
      end

      if arguments[:viewer_can_admin]
        if viewer
          listings = listings.editable_by(viewer)
        else
          # Anonymous user cannot admin any listings, so make sure they get an empty list
          listings = listings.where("false")
        end
      end

      if viewer && viewer.can_admin_marketplace_listings?
        # For an admin using biztools: allow filtering to just a particular user
        if (admin_id = arguments[:admin_id]).present?
          user = Helpers::NodeIdentification.
            typed_object_from_id([Objects::User], admin_id, @context)
          listings = listings.editable_by(user)
        end

        # For an admin using biztools: allow filtering to just a particular org
        if (org_id = arguments[:organization_id]).present?
          org = Helpers::NodeIdentification.
            typed_object_from_id([Objects::Organization], org_id, @context)
          listings = listings.for_org(org)
        end
      end

      if (arguments[:all_states] || arguments[:state].present? || arguments[:states].present?) && viewer
        # It may be legit to allow an empty array here, though GraphQL treats that as non present
        if (states = arguments[:states].presence)
          listings = listings.with_states(states)
        elsif (state = arguments[:state]).present?
          listings = listings.with_state(state)
        end

        # Unless you're an admin, you can only see listings regardless of state if
        # they're listings you own, or if they're approved.
        unless viewer.can_admin_marketplace_listings?
          listings = listings.visible_to(viewer)
        end
      elsif !viewer || !arguments[:viewer_can_admin]
        # Default to listings that are public.
        listings = listings.publicly_listed
      end

      listings = listings.where(slug: arguments[:slugs]) if arguments[:slugs].present?

      listings
    end
  end
end
