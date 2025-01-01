# typed: strict
# frozen_string_literal: true

module Billing::TradeCompliance
  module ContactDependency
    extend ActiveSupport::Concern
    extend T::Helpers

    abstract!

    requires_ancestor { Billing::Contact }

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
      vat_code = self.billable_owner&.trade_screening_record&.vat_code || self.customer&.vat_code
      ::TradeCompliance::TradeScreening::CustomerDetails.new(
        id: trade_screening_request_id,
        first_name: self.first_name,
        last_name: self.last_name,
        entity_name: self.entity_name,
        vat_code: vat_code,
        address1: self.address1,
        address2: self.address2,
        city: self.city,
        region: self.region,
        country_code: self.country_code,
        postal_code: self.postal_code
      )
    end

    sig { returns(T::Boolean) }
    def has_delete_trade_restrictions?
      has_restrictions = AccountScreeningProfile.has_delete_trade_restrictions?(screening_status: self.trade_screening_status)
      return has_restrictions unless billable_owner = self.billable_owner
      return billable_owner.trade_screening_record.has_delete_trade_restrictions? unless billable_owner.feature_enabled?(:read_billing_information_from_contacts)

      has_restrictions || billable_owner.trade_screening_record.has_delete_trade_restrictions?
    end

    private

    sig { returns(TradeCompliance::TradeScreening::AccountType) }
    def trade_screening_account_type
      return TradeCompliance::TradeScreening::AccountType::Individual unless billable_owner = self.billable_owner

      billable_owner.user? ? TradeCompliance::TradeScreening::AccountType::Individual : TradeCompliance::TradeScreening::AccountType::Business
    end

    sig { void }
    def rescreen_on_pii_update
      return if not_screened?

      changed_fields = T.let(saved_changes.keys & Billing::Contact::PII_ATTRIBUTES, T::Array[String])
      return if changed_fields.blank?

      return unless billable_owner = self.billable_owner
      return unless billable_owner.feature_enabled?(:read_billing_information_from_contacts)
      return unless billable_owner.should_perform_live_sdn_rescreening?

      screening_profile = billable_owner.trade_screening_record
      screening_profile.metadata["rescreen_reason"] = "pii_update"
      billable_owner.perform_live_sdn_screening(force: true, account_screening_profile: screening_profile)
    end

    sig { returns(T::Boolean) }
    def has_update_trade_restrictions?
      return true if !not_screened? && !valid_for_trade_screening?
      has_restrictions = AccountScreeningProfile.has_update_trade_restrictions?(screening_status: self.trade_screening_status)
      return has_restrictions unless billable_owner = self.billable_owner
      return billable_owner.trade_screening_record.has_update_trade_restrictions? unless billable_owner.feature_enabled?(:read_billing_information_from_contacts)

      has_restrictions || billable_owner.trade_screening_record.has_update_trade_restrictions?
    end
  end
end
