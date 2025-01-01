# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    class BusinessShippingInformationFormComponent < ApplicationComponent

      sig { returns Business }
      attr_reader :business

      sig { params(business: Business).void }
      def initialize(business:)
        @business = business
      end

      private

      sig { returns(T::Boolean) }
      def render?
        business.shipping_information_required?
      end

      sig { returns(Billing::Contact) }
      memoize def shipping_contact
        business.shipping_contact
      end

      sig { returns(String) }
      def form_path
        if shipping_contact.persisted?
          enterprise_billing_shipping_information_path(business, shipping_contact)
        else
          enterprise_billing_shipping_information_index_path(business)
        end
      end

      sig { returns(Symbol) }
      def form_method
        if shipping_contact.persisted?
          :put
        else
          :post
        end
      end
    end
  end
end
