# typed: true
# frozen_string_literal: true

module Stafftools::Billing::Businesses
  class MeteredBillingSettingsComponent < ApplicationComponent
    extend T::Sig

    include StafftoolsHelper
    include Stafftools::BillingHelper

    attr_reader :business

    sig { params(business: Business).void }
    def initialize(business:)
      @business = business
    end

    private

    def show_metered_via_azure_checkbox?
      business.enterprise_agreements.active.none?
    end
  end
end
