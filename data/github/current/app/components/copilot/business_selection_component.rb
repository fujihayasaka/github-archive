# typed: true
# frozen_string_literal: true

module Copilot
  class BusinessSelectionComponent < ApplicationComponent
    attr_reader :business_type, :businesses, :already_signed_up_businesses, :form_path

    def initialize(business_type:, businesses:, already_signed_up_businesses:, form_path:)
      @business_type = business_type
      @businesses = businesses
      @already_signed_up_businesses = already_signed_up_businesses
      @form_path = form_path
    end

    def business_type_name
      if business_type == "org"
        "organization"
      else
        "enterprise"
      end
    end
  end
end
