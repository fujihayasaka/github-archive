# typed: strict
# frozen_string_literal: true

module Billing::ContactDependency
  include GitHub::Memoizer
  extend T::Helpers

  sig { returns(Billing::Types::BillingInformation) }
  def billing_contact
    T.bind(self, Billing::Types::Account)

    if self.feature_flag_enabled?(:read_billing_information_from_contacts, default: false)
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

    if feature_flag_enabled?(:read_billing_information_from_contacts, default: false)
      contact = billing_contact
      has_valid_contact = contact.persisted? && (skip_validation_errors ? contact.dup : contact).valid_for_trade_screening?
      has_valid_contact &&= contact.validated_for_sales_tax? unless skip_address_validity_check
      return !!has_valid_contact
    end

    has_valid_contact = has_saved_trade_screening_record?(skip_validation_errors:)
    has_valid_contact &&= trade_screening_record.validated_for_sales_tax? unless skip_address_validity_check
    has_valid_contact
  end

  sig { returns(T::Boolean) }
  def has_billing_info_validation_errors?
    T.bind(self, Billing::Types::Account)

    billing_contact.contact_information_stash.errors?
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

    # This is a little confusing but under the hood it:
    # - calls `ensure_trade_screening_record_exists` to create a screening record
    # - calls trade_screening_details that gets the billing and shipping contacts details
    # - and then validates the screening details that include contact details
    # TODO: This should be updated to better reflect what it is doing
    has_valid_contacts = valid_trade_screening_details?
    GitHub.logger.warn("Account does not have valid billing or shipping contact", "gh.account.id" => id) unless has_valid_contacts

    has_valid_contacts
  end

  # Public: check if business has a valid personal profile for financial transactions with any of the address fields entered
  # TODO: Remove this method entirely when removing usages of the read_billing_information_from_contacts flag.
  sig { returns(T::Boolean) }
  def has_saved_billing_contact_with_information?
    T.bind(self, Billing::Types::Account)

    return has_saved_billing_information?(skip_validation_errors: true) if feature_flag_enabled?(:read_billing_information_from_contacts, default: false)

    has_saved_billing_information?(skip_validation_errors: true) && (
      billing_contact.address1.present? ||
      billing_contact.address2.present? ||
      billing_contact.city.present? ||
      billing_contact.region.present? ||
      billing_contact.postal_code.present? ||
      billing_contact.vat_code.present?
    )
  end

  # Public: Removes all customer contacts in addition to:
  #   - clearing the customer VAT code
  #   - removing all payment methods
  #
  # if the customer is allowed to remove billing information. This check includes:
  #   - the customer not having any pii delete trade restrictions
  #   - the customer not having any current plan charges that require payment method/payment information to exist like having upcoming charges
  #
  # these checks are skipped if `skip_validations` is true. Instead we make a best effort to remove the contacts and ignoring any errors that may occur.
  # `skip_validations` should be used sparingly and only for internal system use (like stafftools).
  sig { params(actor: User, skip_validations: T::Boolean).returns(T::Boolean) }
  def remove_billing_information(actor:, skip_validations: false)
    T.bind(self, Billing::Types::Account)
    return trade_screening_record.remove_billing_information(actor:) unless feature_flag_enabled?(:read_billing_information_from_contacts, default: false)

    return true unless customer = billable_owner.customer
    return false unless skip_validations || is_allowed_to_remove_billing_information?
    return false if skip_validations && customer.billing_contact.has_account_delete_trade_restrictions?

    billable_owner.remove_all_payment_methods(actor)
    raise Billing::Contact::ContactDeletionError.new("Removing payment methods failed") if !skip_validations && has_valid_payment_method?(feature_type: :noncommercial)
    succeeded = T.let(!has_valid_payment_method?(feature_type: :noncommercial), T::Boolean)

    with_write do
      customer.contacts.destroy_all
      raise Billing::Contact::ContactDeletionError.new("Removing contacts failed") if !skip_validations && customer.contacts.any?
      succeeded &&= !customer.contacts.any?

      # Customer should be updated second to avoid rescreening
      customer.update(vat_code: nil) if !customer.billing_contact.has_delete_pii_trade_restrictions?
      raise Billing::Contact::ContactDeletionError.new("Clearing vat_code failed") if !skip_validations && customer.vat_code.present?
      succeeded &&= !customer.vat_code.present?
    end

  rescue ActiveRecord::ActiveRecordError, Billing::Contact::ContactDeletionError => exception
    # Log the failure to Splunk
    GitHub.logger.error("billing.contact.remove_billing_information.failed",
      "gh.billing.billable_entity.id": id,
      "gh.billing.billable_entity.type": self.class.name,
      "gh.billing.customer.id": customer&.id,
      "gh.billing.billing_contact.id": customer&.billing_contact&.id,
      "error.message": exception.message,
    )

    # Report the original exception to Sentry
    Failbot.report(exception)

    false
  end

  sig { returns(Customer) }
  def find_or_create_customer
    T.bind(self, Billing::Types::Account)
    billable_owner.customer || with_write { ::Billing::CreateCustomer.perform(billable_owner).customer }
  end
end
