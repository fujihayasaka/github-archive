# typed: strict
# frozen_string_literal: true

module Marketplace
  module Listings
    module SecurityAndCompliance
      extend T::Helpers

      STANDARD_BUSINESS_ID_TYPES = T.let(%w(duns vat ein), T::Array[String])

      requires_ancestor { Marketplace::Listing }

      sig { returns(T::Boolean) }
      def dsa_compliant?
        case trader_self_certification
        when "trader"
          T.cast(trader_address.present?, T::Boolean) &&
            T.cast(trader_id_type.present?, T::Boolean) &&
            T.cast(trader_id.present?, T::Boolean) &&
            has_eu_compliance_attestation? &&
            T.cast(tos_url.present?, T::Boolean) &&
            T.cast(privacy_policy_url.present?, T::Boolean)
        when "non_trader"
          true
        else
          false
        end
      end

      private

      sig { void }
      def validate_dsa_compliance
        # Note: tos_url and privacy_policy_url are part of DSA compliance but we won't invalidate records without them
        # has_eu_compliance_attestation is also required but they can "un-attest", so false is valid
        if trader?
          errors.add(:base, "Business address is required") if trader_address.blank?
          errors.add(:base, "Business id type is required") if trader_id_type.blank?
          errors.add(:base, "Business id is required") if trader_id.blank?
        end
      end

      sig { void }
      def will_save_change_to_dsa_attributes?
        will_save_change_to_trader_self_certification? ||
          will_save_change_to_trader_address? ||
          will_save_change_to_trader_id_type? ||
          will_save_change_to_trader_id? ||
          will_save_change_to_has_eu_compliance_attestation?
      end
    end
  end
end
