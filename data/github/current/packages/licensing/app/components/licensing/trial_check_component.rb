# typed: true
# frozen_string_literal: true

module Licensing
  class TrialCheckComponent < ApplicationComponent

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
        test_selector: "trial-check",
      )
    end

    def render?
      true
    end

    private

    attr_reader :business, :tag

    memoize def trial?
      business.trial?
    end

    def status
      trial? ? :error : :success
    end

    def message
      return "Currently on a trial" if trial?
      "Not on a trial"
    end
  end
end
