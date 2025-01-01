# typed: strict
# frozen_string_literal: true

module Marketplace
  module Serializers
    module App
      extend T::Helpers
      extend Search::RepositoryActionIconHelper

      sig { params(listing: Marketplace::Listing, current_user: T.nilable(::User)).returns(Marketplace::Types::SerializedAppListing) }
      def self.serialize_model(listing, current_user: nil)
        {
          bgColor: listing.bgcolor,
          copilotApp: listing.copilot_app,
          documentationUrl: listing.documentation_url,
          extendedDescription: Platform::Helpers::MarketplaceListingContent.html_for(listing, :extended_description, { current_user: current_user }),
          fullDescription: Platform::Helpers::MarketplaceListingContent.html_for(listing, :full_description, { current_user: current_user }),
          id: T.must(listing.id),
          installationCount: listing.cached_installation_count,
          isVerifiedOwner: listing.verified_owner?,
          listingLogoUrl: listing.logo_url,
          name: listing.name,
          ownerLogin: T.cast(listing.owner&.display_login, T.nilable(String)),
          pricingUrl: listing.pricing_url,
          primaryCategory: T.cast(listing.regular_categories.pluck(:name).first, T.nilable(String)),
          privacyPolicyUrl: listing.privacy_policy_url,
          secondaryCategory: T.cast(listing.regular_categories.pluck(:name).second, T.nilable(String)),
          shortDescription: listing.short_description,
          slug: listing.slug,
          statusUrl: listing.status_url,
          supportUrl: listing.support_url,
          tosUrl: listing.tos_url,
          type: Marketplace::Types::ListingTypes::MarketplaceListing.serialize,
        }
      end

      sig { params(view: ::Search::MarketplaceListingResultView).returns(Marketplace::Types::SerializedAppListing) }
      def self.serialize_search_view(view)
        listing = T.cast(view.marketplace_listing, Marketplace::Listing)

        {
          bgColor: listing.bgcolor,
          copilotApp: listing.copilot_app,
          documentationUrl: listing.documentation_url,
          extendedDescription: view.extended_description,
          fullDescription: view.full_description,
          id: T.must(listing.id),
          installationCount: T.cast(view.installation_count, Integer),
          isVerifiedOwner: T.cast(view.is_verified_owner, T::Boolean),
          listingLogoUrl: listing.logo_url,
          name: listing.name,
          ownerLogin: T.cast(listing.owner&.display_login, T.nilable(String)),
          pricingUrl: listing.pricing_url,
          primaryCategory: T.cast(view.primary_category, T.nilable(String)),
          privacyPolicyUrl: listing.privacy_policy_url,
          secondaryCategory: T.cast(view.secondary_category, T.nilable(String)),
          shortDescription: view.short_description,
          slug: listing.slug,
          statusUrl: listing.status_url,
          supportUrl: listing.support_url,
          tosUrl: listing.tos_url,
          type: Marketplace::Types::ListingTypes::MarketplaceListing.serialize,
        }
      end
    end
  end
end
