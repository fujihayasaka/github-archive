# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    module Customers
      class BillingContactComponent < ApplicationComponent
        sig { params(customer: Customer, billing_contact: T.untyped, show_billing_contact: T::Boolean).void }
        def initialize(customer:, billing_contact:, show_billing_contact:)
          @customer = customer
          @billing_contact = billing_contact
          @show_billing_contact = show_billing_contact
        end

        sig { returns(T::Boolean) }
        def render?
          @show_billing_contact && @billing_contact.present?
        end

        private

        sig { returns(Customer) }
        attr_reader :customer

        sig { returns(T.untyped) }
        attr_reader :billing_contact

        sig { returns(String) }
        def contact_name
          if billing_contact.entity_name.present?
            billing_contact.entity_name
          elsif billing_contact.first_name.present? || billing_contact.last_name.present?
            [billing_contact.first_name, billing_contact.last_name].compact.join(" ")
          else
            "N/A"
          end
        end

        sig { returns(String) }
        def full_address
          parts = [
            billing_contact.address1,
            billing_contact.address2,
            billing_contact.city,
            billing_contact.region,
            billing_contact.postal_code,
            billing_contact.country_code,
          ].compact_blank
          parts.any? ? parts.join(", ") : "No address on file"
        end

        sig { returns(String) }
        def trade_screening_status
          billing_contact.try(:trade_screening_status) || "N/A"
        end

        sig { returns(T.untyped) }
        def address_validated_at
          billing_contact.try(:address_validated_at)
        end

        sig { returns(T.untyped) }
        def vat_code
          billing_contact.try(:vat_code) || customer.vat_code
        end
      end
    end
  end
end
