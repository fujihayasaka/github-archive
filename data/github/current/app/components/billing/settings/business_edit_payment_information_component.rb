# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    class BusinessEditPaymentInformationComponent < ApplicationComponent
      sig { returns(Business) }
      attr_reader :business

      sig { returns(T.nilable(String)) }
      attr_reader :return_to

      sig { returns(T::Boolean) }
      attr_reader :show_form

      sig { returns(T::Boolean) }
      attr_reader :constrained_layout

      sig { params(business: Business, return_to: T.nilable(String), show_form: T::Boolean, constrained_layout: T::Boolean).void }
      def initialize(business:, return_to: nil, show_form: false, constrained_layout: false)
        @business = business
        @return_to = return_to
        @show_form = show_form
        @constrained_layout = constrained_layout
      end

      sig { returns(Billing::Types::BillingInformation) }
      def billing_contact
        business.billing_contact
      end
    end
  end
end
