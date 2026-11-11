# typed: strict
# frozen_string_literal: true

module Biztools
  module MarketplaceListingsHelper
    sig { params(listing: ::Marketplace::Listing).returns(T::Boolean) }
    def render_approval_tab?(listing)
      render_approve_listing?(listing) ||
        render_reject_listing?(listing) ||
        render_approve_creator?(listing)
    end

    sig { params(listing: ::Marketplace::Listing).returns(T::Boolean) }
    def render_approve_listing?(listing)
      listing.can_approve?
    end

    sig { params(listing: ::Marketplace::Listing).returns(T::Boolean) }
    def render_approve_creator?(listing)
      listing.can_approve? && (
        listing.verification_pending_from_draft? ||
          listing.verification_pending_from_unverified? ||
          listing.archived?
      )
    end

    sig { params(listing: ::Marketplace::Listing).returns(T::Boolean) }
    def render_move_to_verified?(listing)
      listing.verified_creator?
    end

    sig { params(listing: ::Marketplace::Listing).returns(T::Boolean) }
    def render_reject_listing?(listing)
      listing.can_reject? || listing.can_redraft?
    end

    sig { params(listing: ::Marketplace::Listing).returns(T::Hash[String, T.nilable(String)]) }
    def prompt_urls(listing)
      {
        support_url: listing.support_email.present? ? nil : listing.support_url,
        privacy_policy_url: listing.privacy_policy_url,
        company_url: listing.company_url,
        documentation_url: listing.documentation_url,
        installation_url: listing.installation_url,
        pricing_url: listing.pricing_url,
        status_url: listing.status_url,
        terms_of_service_url: listing.tos_url,
        demo_url: listing.demo_url,
        onboarding_url: listing.onboarding_url,
      }
    end

    sig { params(listing: ::Marketplace::Listing).returns(T::Array[::Marketplace::ListingScreenshot]) }
    def screenshots(listing)
      listing.screenshots.order(:sequence).first(::Marketplace::ListingScreenshot::SCREENSHOT_LIMIT_PER_LISTING)
    end

    sig { params(listing: ::Marketplace::Listing).returns(T::Array[String]) }
    def required_fields(listing)
      required_fields = prompt_urls(listing).select { |_key, value| value.present? }.keys.map(&:to_s)
      required_fields << "support_email" if listing.support_email.present?
      required_fields << "screenshots" if screenshots(listing).any?
      required_fields
    end
  end
end
