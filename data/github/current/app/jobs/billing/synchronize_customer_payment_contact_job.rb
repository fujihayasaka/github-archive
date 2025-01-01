# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Billing
  class SynchronizeCustomerPaymentContactJob < ApplicationJob
    queue_as :billing

    class SynchronizationFailed < StandardError; end

    def self.country_code_alpha3(country_code)
      Customer.countries.key(country_code)
    end

    def perform(customer)
      payment_details = Billing::PaymentProcessorPaymentDetails.new \
        country_code_alpha3: self.class.country_code_alpha3(customer.country_code_alpha2),
        region: customer.region,
        postal_code: customer.postal_code

      result = with_write { customer.update_payment_contact!(payment_details) }
      raise SynchronizationFailed.new(result.message) unless result.success?
    end
  end
end
