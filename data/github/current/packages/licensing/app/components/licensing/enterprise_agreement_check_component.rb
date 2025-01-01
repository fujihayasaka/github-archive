# typed: true
# frozen_string_literal: true

module Licensing
  class EnterpriseAgreementCheckComponent < ApplicationComponent
    extend T::Sig

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
        test_selector: "enterprise-agreement-check",
      )
    end

    def render?
      true
    end

    private

    attr_reader :business, :tag

    memoize def has_active_vss_enterprise_agreement?
      business.customer.has_active_vss_enterprise_agreement?
    end

    def status
      has_active_vss_enterprise_agreement? ? :error : :success
    end

    def message
      return "There is an active Enterprise Agreement with VSS seats" if has_active_vss_enterprise_agreement?
      "No active Enterprise Agreement with VSS seats"
    end
  end
end
