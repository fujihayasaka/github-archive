# typed: true
# frozen_string_literal: true

module Licensing
  class AzureSubscriptionCheckComponent < ApplicationComponent

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
        test_selector: "azure-subscription-check",
      )
    end

    def render?
      business.pays_via_azure_paper?
    end

    private

    attr_reader :business, :tag

    memoize def has_invalid_azure_subscription?
      business.pays_via_azure_paper? && T.must(business.customer).invalid_azure_subscription_detected?
    end

    def status
      has_invalid_azure_subscription? ? :error : :success
    end

    def message
      return "Azure subscription must be setup" if has_invalid_azure_subscription?
      "Valid azure subscription setup"
    end
  end
end
