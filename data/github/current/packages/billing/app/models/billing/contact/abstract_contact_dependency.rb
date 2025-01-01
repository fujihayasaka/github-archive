# typed: strict
# frozen_string_literal: true

module Billing::Contact::AbstractContactDependency
  extend T::Sig
  extend T::Helpers

  abstract!

  sig { returns(T.any(Billing::Contact, AccountScreeningProfile)) }
  def billing_contact
    owner = T.cast(self, Billing::Types::Account)
    if owner.feature_enabled?(:read_billing_information_from_contacts)
      find_or_create_customer.billing_contact
    else
      owner.trade_screening_record
    end
  end

  private

  sig { returns(Customer) }
  def find_or_create_customer
    owner = T.cast(self, Billing::Types::Account)
    owner.customer || ::Billing::CreateCustomer.perform(owner).customer
  end
end
