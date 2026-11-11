# typed: strict
# frozen_string_literal: true

module Marketplace
  module Listings
    class SecurityAndComplianceFormComponent < ApplicationComponent
      TRANSPARENCY_DISCLOSURE_PLACEHOLDER = <<~PLACEHOLDER
          Provide available details about your extension's safety and security measures. Include any applicable information about:

          - Security Measures: authentication methods, access controls, incident response plans
          - Data Handling: data encryption, data collection and usage, privacy protections, data retention policies, cross-border transfers (if applicable)
          - Compliance: list any compliance certifications, links to reports, and expiration dates (e.g. SOC II/III, ISO 27001, HIPAA, GDPR, FedRAMP)
          - High-Risk Systems: If you declared your extension as high-risk under EU AI Act, also include system accuracy metrics, human oversight procedures, risk monitoring methods and known limitations

          Please link to supporting documentation where available and use H2 headers (##) for better readability.
        PLACEHOLDER

      sig { returns(Marketplace::Listing) }
      attr_reader :listing

      sig { params(listing: Marketplace::Listing).void }
      def initialize(listing:)
        @listing = listing
      end

      private

      sig { returns(String) }
      def trader_inputs_style
        listing.trader? ? "display:block;" : "display:none;"
      end

      sig { returns(String) }
      def id_type_value
        if listing.trader_id_type.blank?
          ""
        elsif standard_id_type_selected?
          listing.trader_id_type
        else
          "other"
        end
      end

      sig { returns(String) }
      def other_id_type_style
        id_type_value == "other" ? "display:block;" : "display:none;"
      end

      sig { returns(String) }
      def repo_url_style
        listing.repository_public? ? "display:block;" : "display:none;"
      end

      sig { returns(String) }
      def other_id_type_value
        if listing.trader_id_type.blank? || standard_id_type_selected?
          ""
        else
          listing.trader_id_type || ""
        end
      end

      sig { returns(T::Boolean) }
      def standard_id_type_selected?
        standard_id_types.include?(listing.trader_id_type)
      end

      sig { returns(T::Array[String]) }
      memoize def standard_id_types
        Marketplace::Listings::SecurityAndCompliance::STANDARD_BUSINESS_ID_TYPES
      end

      sig { returns(T::Boolean) }
      def render_ai_act_section?
        listing.listable_is_copilot_configured?
      end
    end
  end
end
