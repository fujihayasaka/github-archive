# typed: true
# frozen_string_literal: true

module Licensing
  class MeteredGhasCheckComponent < ApplicationComponent

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
        test_selector: "metered-ghas-check",
      )
    end

    def render?
      true
    end

    private

    attr_reader :business, :tag

    def status
      !business.advanced_security_metered_for_entity? ? :error : :success
    end

    def message
      return "Business has volume GHAS" if !business.advanced_security_metered_for_entity?
      "Business has metered GHAS"
    end
  end
end
