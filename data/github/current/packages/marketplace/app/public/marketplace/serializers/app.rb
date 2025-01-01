# typed: strict
# frozen_string_literal: true

module Marketplace
  module Serializers
    module App
      extend T::Helpers
      extend Search::RepositoryActionIconHelper
      extend EscapeHelper

      sig { params(listing: Marketplace::Listing, current_user: T.nilable(::User)).returns(Marketplace::Types::SerializedAppListing) }
      def self.serialize_model(listing, current_user: nil)
        transparency_data = Marketplace::Listings::TransparencyData.new(listing: listing)

        {
          bgColor: listing.bgcolor,
          businessId: transparency_data.business_id,
          categories: serialized_categories_for(listing),
          copilotApp: listing.copilot_app,
          documentationUrl: safe_uri(listing.documentation_url),
          euTrader: transparency_data.eu_trader,
          extendedDescription: Platform::Helpers::MarketplaceListingContent.html_for(listing, :extended_description, { current_user: current_user }),
          fullDescription: Platform::Helpers::MarketplaceListingContent.html_for(listing, :full_description, { current_user: current_user }),
          id: listing.id,
          installationCount: listing.cached_installation_count,
          isAiHighRisk: transparency_data.is_ai_high_risk,
          isVerifiedOwner: listing.verified_owner?,
          listableType: listing.listable_type,
          listingLogoUrl: listing.logo_url,
          llmsInUse: transparency_data.llms_in_use,
          name: listing.name,
          ownerImage: T.cast(listing.owner&.primary_avatar_url(48), T.nilable(String)),
          ownerLogin: T.cast(listing.owner&.display_login, T.nilable(String)),
          ownerSafeProfileName: transparency_data.owner_safe_profile_name,
          ownerType: listing.owner&.class&.name,
          pricingUrl: safe_uri(listing.pricing_url),
          privacyPolicyUrl: transparency_data.privacy_policy_url,
          publisher2faRequired: transparency_data.publisher_2fa_required,
          repositoryVisibility: transparency_data.repository_visibility,
          repositoryUrl: transparency_data.repository_url,
          shortDescription: listing.short_description,
          slug: listing.slug,
          statusUrl: transparency_data.status_url,
          supportEmail: transparency_data.support_email,
          supportUrl: transparency_data.support_url,
          thirdPartyServices: listing.third_party_services,
          tosUrl: transparency_data.tos_url,
          traderAddress: listing.trader_address,
          transparencyDisclosure: transparency_data.transparency_disclosure,
          type: Marketplace::Types::ListingTypes::MarketplaceListing.serialize,
          verifiedProfileDomains: transparency_data.verified_profile_domains,
        }
      end

      sig { params(view: ::Search::MarketplaceListingResultView).returns(Marketplace::Types::SerializedAppPreview) }
      def self.serialize_search_view(view)
        listing = T.cast(view.marketplace_listing, Marketplace::Listing)

        {
          bgColor: listing.bgcolor,
          copilotApp: listing.copilot_app,
          id: listing.id,
          isVerifiedOwner: T.cast(view.is_verified_owner, T::Boolean),
          listingLogoUrl: listing.logo_url,
          name: listing.name,
          shortDescription: view.short_description,
          slug: listing.slug,
          type: Marketplace::Types::ListingTypes::MarketplaceListing.serialize,
        }
      end

      sig { params(listing: Marketplace::Listing).returns(T::Array[{ name: String, slug: String }]) }
      private_class_method def self.serialized_categories_for(listing)
        listing.regular_categories.map { |category| { name: category.name, slug: category.slug } }
      end
    end
  end
end
