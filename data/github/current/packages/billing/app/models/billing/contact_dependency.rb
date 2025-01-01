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

  sig { returns(T::Boolean) }
  def has_saved_billing_information?
    T.bind(self, Billing::Types::Account)

    return true if has_commercial_interaction_restriction?(feature_type: :update_info)
    return false unless billing_contact.persisted?
    return false unless billing_contact.valid_for_trade_screening?

    !billing_contact.contact_information_stash.errors?
  end

  private

  sig { returns(Customer) }
  def find_or_create_customer
    T.bind(self, Billing::Types::Account)

    self.customer || with_write { ::Billing::CreateCustomer.perform(self).customer }
  end
end
