# typed: true # rubocop:disable Sorbet/TrueSigil
# frozen_string_literal: true

module Platform::Objects::Query::Integrations
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  included do
    T.bind(self, T.class_of(Platform::Objects::Query))

    field :integration_listing, Platform::Objects::IntegrationListing, visibility: :internal, description: "Lookup a single Integration listing", null: true do
      argument :slug, String, "Select the listing which matches this slug", required: true
    end

    def integration_listing(**arguments)
      query = ::IntegrationListing

      query = if @context[:viewer] && @context[:viewer].site_admin?
        query.draft_and_published
      else
        query.published
      end

      query.find_by(slug: arguments[:slug])
    end

    field :integration_listings, Connections.define(Platform::Objects::IntegrationListing), visibility: :internal, description: "Lookup Integration listings", null: false, connection: true do
      argument :slug, String, "Select only listings with the given category slug.", required: false
      argument :query, String, "Select listings whose name or description matches the query.", required: false
    end

    def integration_listings(**arguments)
      query = ::IntegrationListing.
        with_feature(arguments[:slug]).
        matches_name_or_description(arguments[:query])

      if @context[:viewer] && @context[:viewer].site_admin?
        query.draft_and_published
      else
        query.published
      end
    end

    field :integration_categories, [Objects::IntegrationFeature], visibility: :internal, description: "Get alphabetically sorted list of Integration categories", null: false do
      argument :slug, String, "An optional category slug to select a specific category.", required: false
    end

    def integration_categories(**arguments)
      categories = ::IntegrationFeature

      if slug = arguments[:slug]
        categories = categories.where(slug: slug)
      end

      categories.at_least_visible.order(:name)
    end
  end
end
