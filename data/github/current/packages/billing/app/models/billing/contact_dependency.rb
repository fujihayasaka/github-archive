# typed: strict
# frozen_string_literal: true

module Billing::ContactDependency
  extend T::Helpers

  sig { returns(T.any(Billing::Contact, AccountScreeningProfile)) }
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

  private

  sig { returns(Customer) }
  def find_or_create_customer
    T.bind(self, Billing::Types::Account)

    self.customer || with_write { ::Billing::CreateCustomer.perform(self).customer }
  end
end
