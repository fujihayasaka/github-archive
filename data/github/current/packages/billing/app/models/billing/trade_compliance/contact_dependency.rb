# typed: strict
# frozen_string_literal: true

module Billing::TradeCompliance
  module ContactDependency
    extend ActiveSupport::Concern
    extend T::Helpers

    abstract!

    requires_ancestor { Billing::Contact }

    class SyncToScreeningProfileError < StandardError; end

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

    # Check if this contact or the billable owner has delete trade restrictions
    sig { returns(T::Boolean) }
    def has_delete_trade_restrictions?
      has_restrictions = AccountScreeningProfile.delete_restricted?(screening_status: trade_screening_status)
      return has_restrictions unless billable_owner = self.billable_owner

      has_restrictions || billable_owner.trade_compliance_delete_restriction?
    end

    sig { params(changed_attributes: T::Hash[T.any(String, Symbol), T.untyped]).void }
    def rescreen_on_pii_update(changed_attributes: saved_changes)
      return unless pii_data_changed?(changed_attributes:)
      return unless billable_owner = self.billable_owner
      return unless billable_owner.feature_enabled?(:read_billing_information_from_contacts)
      return unless billable_owner.should_perform_live_sdn_rescreening?
      return unless billable_owner.valid_trade_screening_details?

      screening_profile = billable_owner.trade_screening_record
      screening_profile.changed_pii_fields = changed_attributes.keys & Billing::Contact::PII_ATTRIBUTES
      screening_profile.metadata["rescreen_reason"] = "pii_update"
      billable_owner.perform_live_sdn_screening(force: true, account_screening_profile: screening_profile)
    end

    # Syncs contact data to the owner's AccountScreeningProfile
    sig { params(changed_attributes: T::Hash[T.any(String, Symbol), T.untyped]).void }
    def sync_to_trade_screening_record(changed_attributes: saved_changes)
      return unless billing?
      return unless pii_data_changed?(changed_attributes:) || destroyed? || customer&.destroyed?
      return unless billable_owner = self.billable_owner
      # read_billing_information_from_contacts means customers are directly reading and writing from `Billing::Contact`
      # write_billing_information_from_contacts means customers should sync their data back to `AccountScreeningProfile`
      return unless billable_owner.feature_enabled?(:read_billing_information_from_contacts)
      return unless billable_owner.feature_enabled?(:write_billing_information_from_contacts)

      # screening profile table has validations on these fields not being null so we need to store them as blanks
      screening_profile = billable_owner.trade_screening_record
      billing_info = {
        first_name: first_name.to_s,
        last_name: last_name.to_s,
        entity_name: entity_name.to_s,
        address1: address1.to_s,
        address2: address2.to_s,
        city: city.to_s,
        region: region.to_s,
        postal_code: postal_code.to_s,
        country_code: country_code.to_s,
        billing_address_validated_at: address_validated_at,
      }
      billing_info.transform_values! { |_| "" } if destroyed?
      billing_info[:vat_code] = customer&.destroyed? ? "" : vat_code.to_s
      screening_profile.assign_attributes(billing_info)
      screening_profile.metadata.merge!("synced_to_screening_profile" => "true") unless screening_profile.metadata["synced_to_screening_profile"]

      # we need to skip validations here because if `Billing::Contact` is a partial records then we should still save that on the screening profile
      unless screening_profile.save(validate: false)
        Failbot.report(
          SyncToScreeningProfileError.new("Failed to sync contact to screening record due to #{screening_profile.errors.full_messages.to_sentence}"),
          "gh.billing.contact.id": id,
          "gh.trade_compliance.trade_screening.id": screening_profile.id,
          "gh.trade_compliance.trade_screening.external_id": screening_profile.external_uuid
        )
      end
    end

    private

    sig { returns(TradeCompliance::TradeScreening::AccountType) }
    def trade_screening_account_type
      return TradeCompliance::TradeScreening::AccountType::Individual unless billable_owner = self.billable_owner

      billable_owner.user? ? TradeCompliance::TradeScreening::AccountType::Individual : TradeCompliance::TradeScreening::AccountType::Business
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
