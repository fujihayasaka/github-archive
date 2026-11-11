# typed: strict
# frozen_string_literal: true

module Marketplace
  module Listings
    class TransparencyData
      include EscapeHelper

      sig { returns(Marketplace::Listing) }
      attr_reader :listing

      sig { params(listing: Marketplace::Listing).void }
      def initialize(listing:)
        @listing = listing
      end

      delegate :owner, :trader_id, :trader_id_type, to: :listing, private: true

      sig { returns(T.nilable(String)) }
      def publisher_2fa_required
        return "Not applicable - Individual publisher" if owner&.user?
        return unless owner&.organization?

        if T.cast(owner, Organization).two_factor_requirement_enabled?
          "Yes - Publisher organization requires 2FA"
        else
          "No - Publisher organization does not require 2FA"
        end
      end

      sig { returns(T::Array[String]) }
      def verified_profile_domains
        return [] unless owner&.organization?

        T.cast(owner, Organization).verified_profile_domains
      end

      sig { returns(T.nilable(String)) }
      def repository_visibility
        listing.repository_visibility unless listing.repository_unspecified?
      end

      sig { returns(T.nilable(String)) }
      def repository_url
        safe_uri(listing.repository_url) if listing.repository_public?
      end

      sig { returns(T.nilable(String)) }
      def transparency_disclosure
        GitHub::Goomba::MarkdownPipeline.to_html(listing.transparency_disclosure)
      end

      sig { returns(T.nilable(String)) }
      def llms_in_use
        listing.llms_in_use if listing.listable_is_copilot_configured?
      end

      sig { returns(T.nilable(String)) }
      def is_ai_high_risk # rubocop:disable Naming/PredicatePrefix
        return unless listing.listable_is_copilot_configured? && !listing.ai_risk_level_unspecified?
        listing.ai_risk_level == "high" ? "Yes" : "No"
      end

      sig { returns(T.nilable(String)) }
      def support_url
        return if listing.support_email.present?
        safe_uri(listing.support_url)
      end

      sig { returns(T.nilable(String)) }
      def support_email
        return if listing.support_email.blank?
        T.must(listing.support_email).sub(/\Amailto:/, "")
      end

      sig { returns(T.nilable(String)) }
      def privacy_policy_url
        safe_uri(listing.privacy_policy_url)
      end

      sig { returns(T.nilable(String)) }
      def tos_url
        safe_uri(listing.tos_url)
      end

      sig { returns(T.nilable(String)) }
      def business_id
        return unless trader_id.present? && trader_id_type.present?

        if Marketplace::Listings::SecurityAndCompliance::STANDARD_BUSINESS_ID_TYPES.include?(trader_id_type)
          "#{trader_id_type.upcase} #: #{trader_id}"
        else
          "#{trader_id_type}: #{trader_id}"
        end
      end

      sig { returns(T.nilable(String)) }
      def owner_safe_profile_name
        owner&.safe_profile_name
      end

      sig { returns(T.nilable(String)) }
      def status_url
        safe_uri(listing.status_url)
      end

      sig { returns(T.nilable(String)) }
      def eu_trader
        return unless listing.trader_self_certification
        if listing.trader?
          "Yes - Classifies as a trader in the European Union"
        else
          "No - Does not classify as a trader in the European Union"
        end
      end

      sig { returns(T.nilable(String)) }
      def indemnity_status
        return unless listing.copilot_app
        "Not covered by Microsoft's indemnity policy. All other Copilot features retain indemnity coverage."
      end
    end
  end
end
