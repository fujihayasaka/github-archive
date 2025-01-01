# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module MarketplaceListingOwner
      include Platform::Interfaces::Base
      description "Represents an owner of a MarketplaceListing."
      visibility :internal

      database_id_field

      field :login, String, "The username used to login.", null: false

      field :name, String, description: "The owner's public profile name.", null: true

      def name
        @object.async_profile.then do |profile|
          profile.try(:name)
        end
      end

      field :avatar_url, Scalars::URI, description: "A URL pointing to the owner's public avatar.", null: false do
        T.bind(self, GraphQL::Schema::Member::HasArguments)
        argument :size, Integer, "The size of the resulting square image.", required: false
      end

      def avatar_url(**arguments)
        @object.primary_avatar_url(arguments[:size])
      end

      field :active_listing_plan, Objects::MarketplaceListingPlan, description: <<~DESCRIPTION, null: true do
          Returns the listing plan for which this owner has an active subscription, for the
          specified Marketplace listing.
        DESCRIPTION
        T.bind(self, GraphQL::Schema::Member::HasArguments)
        argument :listing_slug, String, "The short name of the listing used in its URL.", required: true
      end

      def active_listing_plan(**arguments)
        @object.async_active_listing_plan(arguments[:listing_slug])
      end

      field :verified_domains_list, [String], description: "Verified domains available to this organization.", null: false

      def verified_domains_list
        return [] unless @object.organization?
        @object.async_business.then do
          @object.email_eligible_domain_urls(include_approved: false)
        end
      end
    end
  end
end
