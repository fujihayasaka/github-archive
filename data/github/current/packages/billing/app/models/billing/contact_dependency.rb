# typed: strict
# frozen_string_literal: true

module Billing::ContactDependency
  include GitHub::Memoizer
  extend T::Helpers

  sig { returns(Billing::Types::BillingInformation) }
  def billing_contact
    T.bind(self, Billing::Types::Account)

    if self.feature_enabled?(:read_billing_information_from_contacts)
      find_or_create_customer.billing_contact
    else
      self.trade_screening_record
    end
  end

  sig { returns(Billing::Contact) }
  def shipping_contact
    find_or_create_customer.shipping_contact
  end

  sig { overridable.params(address_type: String).returns(Billing::ContactUpdateStash) }
  def contact_information_stash(address_type)
    Billing::ContactUpdateStash.retrieve_stashed_update_for(T.cast(self, Billing::Types::Account), address_type)
  end

  sig { params(skip_validation_errors: T::Boolean, skip_address_validity_check: T::Boolean).returns(T::Boolean) }
  def has_saved_billing_information?(skip_validation_errors: false, skip_address_validity_check: false)
    T.bind(self, Billing::Types::Account)
    return true if has_commercial_interaction_restriction?(feature_type: :update_info)

    if feature_enabled?(:read_billing_information_from_contacts)
      contact = billing_contact
      has_valid_contact = contact.persisted? && contact.valid_for_trade_screening?
      has_valid_contact &&= contact.validated_for_sales_tax? unless skip_address_validity_check
      return false unless has_valid_contact

      return !contact.contact_information_stash.errors?
    end

    has_valid_contact = has_saved_trade_screening_record?(skip_validation_errors:)
    has_valid_contact &&= trade_screening_record.validated_for_sales_tax? unless skip_address_validity_check
    has_valid_contact
  end

  # Public: Check if an account has been trade screened and has saved billing information
  #   noncommercial payment checks will be skipped
  sig { params(feature_type: Symbol).returns(T::Boolean) }
  def has_valid_payment_information?(feature_type: :default)
    T.bind(self, Billing::Types::Account)

    # For non-commercial features, we skip the contact validation checks
    return true if feature_type == :noncommercial

    # Regardless of the read_billing_information_from_contacts feature flag, we always require the account to be trade screened
    unless trade_compliance_screened?
      GitHub.logger.warn("Account is not trade screened", "gh.account.id" => id, "gh.trade_screening.external_id" => trade_screening_record.external_uuid)
      return false
    end

    has_valid_contacts = if feature_enabled?(:enhanced_billing_info_validation)
      valid_trade_screening_details?
    else
      has_valid_trade_screening_record?(skip_validation_errors: true)
    end
    GitHub.logger.warn("Account does not have valid billing or shipping contact", "gh.account.id" => id) unless has_valid_contacts

    has_valid_contacts
  end

  # Public: check if business has a valid personal profile for financial transactions with any of the address fields entered
  sig { returns(T::Boolean) }
  def has_saved_billing_contact_with_information?
    T.bind(self, Billing::Types::Account)

    return has_saved_billing_information? if feature_enabled?(:read_billing_information_from_contacts)

    has_saved_billing_information?(skip_validation_errors: true) && (
      billing_contact.address1.present? ||
      billing_contact.address2.present? ||
      billing_contact.city.present? ||
      billing_contact.region.present? ||
      billing_contact.postal_code.present? ||
      billing_contact.vat_code.present?
    )
  end

  sig { returns(Customer) }
  def find_or_create_customer
    T.bind(self, Billing::Types::Account)
    billable_owner = self.billable_owner

    billable_owner.customer || with_write { ::Billing::CreateCustomer.perform(billable_owner).customer }
  end
end
