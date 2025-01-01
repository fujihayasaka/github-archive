# typed: true
# frozen_string_literal: true

module Licensing
  class MeteredLicensingCheckComponent < ApplicationComponent

    sig { params(business: Business, tag: Symbol).void }
    def initialize(business:, tag: :li)
      @business = business
      @tag = tag
    end

    def call
      render Stafftools::StatusListItemComponent.new(
        status: status,
        message: message,
        tag: tag,
        test_selector: "metered-licensing-check",
      )
    end

    def render?
      true
    end

    private

    attr_reader :business, :tag

    def status
      business.metered_plan? ? :error : :success
    end

    def message
      return "Business has metered GHE" if business.metered_plan?
      "Business has volume GHE"
    end
  end
end
