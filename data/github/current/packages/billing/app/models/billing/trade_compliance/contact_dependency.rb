# typed: strict
# frozen_string_literal: true

module Billing::TradeCompliance
  module ContactDependency
    extend ActiveSupport::Concern
    extend T::Helpers

    abstract!

    requires_ancestor { Billing::Contact }

    class SyncToScreeningProfileError < StandardError; end
    class ResetScreeningProfileStatusError < StandardError; end

    included do
      T.bind(self, T.class_of(Billing::Contact))

      # Trade screening validations
      validate :valid_for_individual_trade_screening, on: :individual_trade_screening
      validate :valid_for_entity_trade_screening, on: :entity_trade_screening

      private

      sig { void }
      def valid_for_individual_trade_screening
        details = customer_details

        errors.add(:first_name, details.validate_first_name) if details.validate_first_name.present?
        errors.add(:last_name, details.validate_last_name) if details.validate_last_name.present?
        valid_for_trade_screening(details: details)
      end

      sig { void }
      def valid_for_entity_trade_screening
        details = customer_details

        errors.add(:entity_name, details.validate_entity_name) if details.validate_entity_name.present?
        errors.add(:vat_code, details.validate_vat_code) if details.validate_vat_code.present?
        valid_for_trade_screening(details: details)
      end

      sig { params(details: ::TradeCompliance::TradeScreening::CustomerDetails).void }
      def valid_for_trade_screening(details:)
        errors.add(:address1, details.validate_address1) if details.validate_address1.present?
        errors.add(:address2, details.validate_address2) if details.validate_address2.present?
        errors.add(:city, details.validate_city) if details.validate_city.present?
        errors.add(:country_code, details.validate_country_code) if details.validate_country_code.present?
        errors.add(:postal_code, details.validate_postal_code) if details.validate_postal_code.present?
        errors.add(:region, details.validate_region) if details.validate_region.present?
      end
    end

    # Checks if the contact is valid based on the owner type
    sig { params(owner_type: T.nilable(Symbol)).returns(T::Boolean) }
    def valid_for_trade_screening?(owner_type: nil)
      symbolized_owner_type = if owner_type.present?
        owner_type
      else
        individual_owned? ? :individual_trade_screening : :entity_trade_screening
      end

      case symbolized_owner_type
      when :individual_trade_screening
        valid_for_individual_trade_screening
      else
        valid_for_entity_trade_screening
      end
      errors.blank?
    end

    sig { returns(T::Boolean) }
    def individual_owned?
      trade_screening_account_type == TradeCompliance::TradeScreening::AccountType::Individual
    end

    sig { returns(String) }
    def trade_screening_request_id
      return id.to_s unless billing?
      return id.to_s unless billable_owner = self.billable_owner

      # Microsoft requires hardcoded request ID string for billing contacts, while any additional contact types
      # can set whatever request ID they want
      billable_owner.user? ? "IndName_IndAddr" : "OrgName_OrgAddr"
    end

    sig { returns(::TradeCompliance::TradeScreening::CustomerDetails) }
    def customer_details
      ::TradeCompliance::TradeScreening::CustomerDetails.new(
        id: trade_screening_request_id,
        first_name: first_name,
        last_name: last_name,
        entity_name: entity_name,
        vat_code: vat_code,
        address1: address1,
        address2: address2,
        city: city,
        region: region,
        country_code: country_code,
        postal_code: postal_code
      )
    end

    # Check if this contact or the billable owner has update trade restrictions
    sig { returns(T::Boolean) }
    def has_update_trade_restrictions?
      valid_contact_required = is_trade_screened? && !valid_for_trade_screening?
      return true if valid_contact_required

      contact_has_restrictions = persisted? && AccountScreeningProfile.has_update_trade_restrictions?(screening_status: trade_screening_status)
      account_has_restrictions = !!billable_owner&.has_update_trade_restrictions?
      contact_has_restrictions || account_has_restrictions
    end

    # Check if this contact or the billable owner has delete trade restrictions
    sig { returns(T::Boolean) }
    def has_delete_pii_trade_restrictions?
      has_restrictions = AccountScreeningProfile.has_delete_pii_trade_restrictions?(screening_status: trade_screening_status)
      return has_restrictions unless billable_owner = self.billable_owner

      has_restrictions || billable_owner.trade_compliance_pii_delete_restriction?
    end

    sig { returns(T::Boolean) }
    def has_account_delete_trade_restrictions?
      has_restrictions = AccountScreeningProfile.delete_restricted?(screening_status: trade_screening_status)
      return has_restrictions unless billable_owner = self.billable_owner
      has_restrictions || billable_owner.trade_compliance_account_delete_restriction?
    end

    sig { void }
    def reset_trade_screening_status
      return unless billable_owner = self.billable_owner

      screening_profile = billable_owner.trade_screening_record
      unless screening_profile.reset_trade_screening_status
        Failbot.report(
          ResetScreeningProfileStatusError.new("Failed to reset screening record screening status due to #{screening_profile.errors.full_messages.to_sentence}"),
          "gh.billing.contact.id": id,
          "gh.trade_compliance.trade_screening.id": screening_profile.id,
          "gh.trade_compliance.trade_screening.external_id": screening_profile.external_uuid
        )
      end
    end

    sig { params(changed_attributes: T::Hash[T.any(String, Symbol), T.untyped]).void }
    def rescreen_on_pii_update(changed_attributes: saved_changes)
      return unless pii_data_changed?(changed_attributes:)
      return unless billable_owner = self.billable_owner
      return unless billable_owner.feature_flag_enabled?(:read_billing_information_from_contacts, default: false)
      return unless billable_owner.should_perform_live_sdn_rescreening?
      return unless billable_owner.valid_trade_screening_details?
      return if has_update_trade_restrictions?

      screening_profile = billable_owner.trade_screening_record
      screening_profile.changed_pii_fields = changed_attributes.keys & Billing::Contact::PII_ATTRIBUTES
      screening_profile.metadata["rescreen_reason"] = "pii_update"
      billable_owner.perform_live_sdn_screening(force: true, account_screening_profile: screening_profile)
    end

    private

    sig { returns(TradeCompliance::TradeScreening::AccountType) }
    def trade_screening_account_type
      return TradeCompliance::TradeScreening::AccountType::Individual unless billable_owner = self.billable_owner

      billable_owner.user? ? TradeCompliance::TradeScreening::AccountType::Individual : TradeCompliance::TradeScreening::AccountType::Business
    end

    sig { returns(T::Boolean) }
    def is_trade_screened?
      return false if !billable_owner&.live_sdn_screening_enabled?
      return true if persisted? && !not_screened?
      !!billable_owner&.trade_compliance_screened?
    end
  end
end
