# typed: strict
# frozen_string_literal: true

module Billing::Stafftools
  class AddressValidationComponent < ApplicationComponent
    sig { returns(T.nilable(Customer)) }
    attr_reader :customer

    sig { params(customer: T.nilable(Customer)).void }
    def initialize(customer:)
      @customer = customer
    end

    sig { returns(String) }
    def validate_address_form_path
      stafftools_billing_address_validation_path(customer_id: T.must(customer).id)
    end

    private

    sig { returns(T::Boolean) }
    def render?
      return false unless customer = self.customer
      !customer.has_valid_address_for_tax?
    end
  end
end
