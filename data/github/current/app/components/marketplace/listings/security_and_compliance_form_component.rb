# typed: strict
# frozen_string_literal: true

module Marketplace
  module Listings
    class SecurityAndComplianceFormComponent < ApplicationComponent
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
          T.must(listing.trader_id_type)
        else
          "other"
        end
      end

      sig { returns(String) }
      def other_id_type_style
        id_type_value == "other" ? "display:block;" : "display:none;"
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
        Marketplace::Listings::SecurityAndCompliance::STANDARD_BUSINESS_ID_TYPES.include?(listing.trader_id_type)
      end
    end
  end
end
