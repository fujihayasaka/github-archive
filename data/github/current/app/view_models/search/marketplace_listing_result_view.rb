# typed: true
# frozen_string_literal: true

module Search
  class MarketplaceListingResultView
    include EscapeHelper
    include UrlHelpers

    attr_reader :id, :name, :full_description, :created, :updated, :primary_category, :state,
                :marketplace_listing, :secondary_category, :short_description,
                :extended_description, :free, :installation_count, :type, :recommended, :is_verified_owner,
                :slug, :model_name, :owner_login, :resource_path, :listing_logo_url
    alias :created_at :created
    alias :updated_at :updated

    # Create a new MarketplaceListingResultView from a `marketplace_listing` document hash
    # returned from the ElasticSearch index.
    #
    # hash - Document Hash returned by ElasticSearch
    #
    def initialize(hash)
      source = hash["_source"]

      @id = hash["_id"]
      @marketplace_listing = hash["_model"]
      @name = source["name"]
      @full_description = source["full_description"]
      @short_description = source["short_description"]
      @extended_description = source["extended_description"]
      @free = source["free"]
      @primary_category = source["primary_category"]
      @secondary_category = source["secondary_category"]
      @state = source["state"]
      @created = Time.parse(source["created_at"])
      @updated = Time.parse(source["updated_at"])
      @highlights = hash["highlight"]
      @installation_count = source["installation_count"]
      @type = tool_type
      @recommended = source["is_recommended"]
      @is_verified_owner = source["is_verified_owner"]
      @slug = @marketplace_listing.slug
      @model_name = Marketplace::Listing.to_s
      @owner_login = source["owner_login"]
      @resource_path = marketplace_listing_path(listing_slug: @marketplace_listing.slug)
      @listing_logo_url = @marketplace_listing.logo_url
    end

    def free?
      free
    end

    def logo_url(size: 400)
      marketplace_listing.primary_avatar_url(size)
    end

    def tool_type
      "marketplace_listing"
    end

    # Returns true if there are highlight fragments for this listing. The
    # highlight fragments contain text from the various listing fields with the
    # relevant search terms surrounded by <em> tags.
    def highlights?
      !@highlights.nil?
    end

    # Return the listing name. The name may or may not contain
    # highlight tags, but either way it has been HTML escaped and is html_safe.
    #
    # Returns an HTML escaped name String.
    def hl_name
      @hl_name ||= hl_description("name.ngram", @name)
    end

    # Return the listing short_description. The short_description may or may not contain
    # highlight tags, but either way it has been HTML escaped and is html_safe.
    #
    # Returns an HTML escaped short_description String.
    def hl_short_description
      @hl_short_description ||= hl_description("short_description", @short_description)
    end

    # Return the listing full_description. The full_description may or may not contain
    # highlight tags, but either way it has been HTML escaped and is html_safe.
    #
    # Returns an HTML escaped full_description String.
    def hl_full_description
      @hl_full_description ||= hl_description("full_description", @full_description)
    end

    # Return the listing extended_description. The extended_description may or may not contain
    # highlight tags, but either way it has been HTML escaped and is html_safe.
    #
    # Returns an HTML escaped extended_description String.
    def hl_extended_description
      @hl_extended_description ||= hl_description("extended_description", @extended_description)
    end

    def marketplace_listing_for_frontend_rendering(listing)
      {
        id: listing.id,
        state: listing.state,
        name: listing.name,
        slug: listing.slug,
        short_description: listing.short_description,
        full_description: listing.full_description,
        extended_description: listing.extended_description,
        primary_category_id: listing.primary_category_id,
        secondary_category_id: listing.secondary_category_id,
        privacy_policy_url: listing.privacy_policy_url,
        tos_url: listing.tos_url,
        company_url: listing.company_url,
        status_url: listing.status_url,
        support_url: listing.support_url,
        documentation_url: listing.documentation_url,
        pricing_url: listing.pricing_url,
        bgcolor: listing.bgcolor,
        light_text: listing.light_text,
        learn_more_url: listing.learn_more_url,
        installation_url: listing.installation_url,
        how_it_works: listing.how_it_works,
        hero_card_background_image_id: listing.hero_card_background_image_id,
        direct_billing_enabled: listing.direct_billing_enabled,
        by_github: listing.by_github,
        listable_type: listing.listable_type,
        listable_id: listing.listable_id,
        copilot_app: listing.copilot_app,
      }
    end

    def for_frontend_rendering
      {
        type: @type,
        id: @id,
        state: @state,
        name: @name,
        free: @free,
        primary_category: @primary_category,
        secondary_category: @secondary_category,
        is_verified_owner: @is_verified_owner,
        slug: @slug,
        owner_login: @owner_login,
        resource_path: @resource_path,
        installation_count: @installation_count,
        full_description: @full_description,
        short_description: @short_description,
        extended_description: @extended_description,
        listing_logo_url: @listing_logo_url,
        recommended: @recommended,
        marketplace_listing: {
          listing: marketplace_listing_for_frontend_rendering(@marketplace_listing),
        }
      }
    end

    private

    def hl_description(key, value)
      if highlights? && @highlights.key?(key)
        GitHub::Goomba::HighlightedSearchResultPipeline.to_html(@highlights[key].first)
      else
        formatted = GitHub::Goomba::DescriptionPipeline.to_html(value.to_s)
        HTMLTruncator.new(formatted, 350).to_html(wrap: false)
      end
    end
  end  # MarketplaceListingResultView
end  # Search
