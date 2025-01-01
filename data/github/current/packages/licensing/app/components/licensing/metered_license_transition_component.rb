# typed: strict
# frozen_string_literal: true

module Licensing
  class MeteredLicenseTransitionComponent < ApplicationComponent

    sig { returns(Business) }
    attr_reader :business

    sig { returns(User) }
    attr_reader :current_user

    sig { returns(T.nilable(Licensing::LicensingModelTransition)) }
    attr_reader :transition

    sig { params(business: Business, current_user: User, transition: T.nilable(Licensing::LicensingModelTransition)).void }
    def initialize(business:, current_user:, transition: nil)
      @business = business
      @current_user = current_user
      @transition = transition
    end

    sig { returns(T.nilable(T::Boolean)) }
    memoize def can_transition_to_metered?
      return false if business.metered_plan?
      return false if business.trial?

      customer = T.must(business.customer)
      return false if customer.has_active_vss_enterprise_agreement?
      return false if business.pays_via_azure_paper? && customer.invalid_azure_subscription_detected?

      true
    end

    sig { returns(T::Boolean) }
    memoize def can_transition_to_volume?
      business.metered_plan?
    end

    sig { returns(T::Boolean) }
    def show_unbundle_ghas?
      business.advanced_security_products_bundled?
    end
  end
end
