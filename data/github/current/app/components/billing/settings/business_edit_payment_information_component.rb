# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class BusinessEditPaymentInformationComponent < ApplicationComponent
      attr_reader :business, :return_to, :show_form

      def initialize(business:, return_to: nil, show_form: false)
        @business = business
        @return_to = return_to
        @show_form = show_form
      end
    end
  end
end
