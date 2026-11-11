# typed: strict
# frozen_string_literal: true

module Marketplace
  module Listings
    module SecurityAndCompliance
      extend T::Helpers

      STANDARD_BUSINESS_ID_TYPES = T.let(%w(duns vat), T::Array[String])

      requires_ancestor { Marketplace::Listing }

      sig { returns(T::Boolean) }
      def dsa_compliant?
        case trader_self_certification
        when "trader"
          T.cast(trader_address.present?, T::Boolean) &&
            T.cast(trader_id_type.present?, T::Boolean) &&
            T.cast(trader_id.present?, T::Boolean) &&
            has_eu_compliance_attestation? &&
            T.cast(privacy_policy_url.present?, T::Boolean)
        when "non_trader"
          true
        else
          false
        end
      end

      sig { returns(T::Boolean) }
      def ai_compliant?
        return false if ai_risk_level_unspecified?
        return false if llms_in_use.blank?

        is_eu_ai_act_compliant?
      end

      sig { returns(T::Boolean) }
      def security_complete?
        return false if privacy_policy_url.blank?
        return false if invalid_tos?
        return false if third_party_services.blank?
        return false if repository_unspecified?
        return false if invalid_transparency_disclosure?

        true
      end

      sig { returns(T::Boolean) }
      def security_and_compliance_completed?
        return false if listable_is_copilot_configured? && !ai_compliant?

        dsa_compliant? && security_complete?
      end

      sig { returns(T::Boolean) }
      def listable_is_copilot_configured?
        return false unless listable.is_a?(Integration)
        listable.agent_configured?
      end

      private

      sig { void }
      def validate_dsa_compliance
        return if draft? || !trader?

        # Note: privacy_policy_url are part of DSA compliance but we won't invalidate records without them
        # has_eu_compliance_attestation is also required but they can "un-attest", so false is valid
        errors.add(:base, "Business address is required") if trader_address.blank?
        errors.add(:base, "Business id type is required") if trader_id_type.blank?
        errors.add(:base, "Business id is required") if trader_id.blank?
      end

      sig { returns(T::Boolean) }
      def will_save_change_to_dsa_attributes?
        will_save_change_to_trader_self_certification? ||
          will_save_change_to_trader_address? ||
          will_save_change_to_trader_id_type? ||
          will_save_change_to_trader_id? ||
          will_save_change_to_has_eu_compliance_attestation?
      end

      sig { void }
      def validate_ai_compliance
        return if draft?

        # is_eu_ai_act_compliant is also required but they can "un-attest", so false is valid
        errors.add(:base, 'You must specify if your AI system is classified as "high-risk"') if ai_risk_level_unspecified?
        errors.add(:base, "You must list all LLMs that your extension uses") if llms_in_use.blank?
      end

      sig { returns(T::Boolean) }
      def will_save_change_to_ai_attributes?
        will_save_change_to_ai_risk_level? || will_save_change_to_llms_in_use? || will_save_change_to_is_eu_ai_act_compliant?
      end

      sig { void }
      def validate_security_attributes
        return if draft?

        errors.add(:base, "You must add a privacy policy URL") if privacy_policy_url.blank?
        errors.add(:base, "You must add a terms of service URL") if invalid_tos?
        errors.add(:base, "You must specify third party services") if third_party_services.blank?
        errors.add(:base, "You must add a transparency disclosure") if invalid_transparency_disclosure?
      end

      sig { returns(T::Boolean) }
      def will_save_change_to_security_attributes?
        will_save_change_to_third_party_services? ||
          will_save_change_to_repository_visibility? ||
          will_save_change_to_transparency_disclosure? ||
          will_save_change_to_privacy_policy_url? ||
          will_save_change_to_tos_url?
      end

      sig { returns(T::Boolean) }
      def invalid_tos?
        listable_is_copilot_configured? && tos_url.blank?
      end

      sig { returns(T::Boolean) }
      def invalid_transparency_disclosure?
        ai_risk_level_high? && transparency_disclosure.blank?
      end
    end
  end
end
