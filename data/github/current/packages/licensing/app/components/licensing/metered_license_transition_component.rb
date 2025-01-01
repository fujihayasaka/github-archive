# typed: strict
# frozen_string_literal: true

module Licensing
  class MeteredLicenseTransitionComponent < ApplicationComponent
    extend T::Sig

    sig { returns(Business) }
    attr_reader :business

    sig { returns(T.nilable(Licensing::LicensingModelTransition)) }
    attr_reader :transition

    sig { params(business: Business, transition: T.nilable(Licensing::LicensingModelTransition)).void }
    def initialize(business:, transition: nil)
      @business = business
      @transition = transition
    end

    sig { returns(T.nilable(T::Boolean)) }
    memoize def can_transition_to_metered?
      !business.metered_plan? &&
        !business.trial? &&
        !T.must(business.customer).has_active_vss_enterprise_agreement?
    end

    sig { returns(T::Boolean) }
    memoize def can_transition_to_volume?
      business.metered_plan?
    end
  end
end
