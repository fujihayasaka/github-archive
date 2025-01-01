# typed: strict
# frozen_string_literal: true

module Licensing
  class GhasTransitionComponent < ApplicationComponent

    sig { returns(Business) }
    attr_reader :business

    sig { returns(T.nilable(Licensing::LicensingModelTransition)) }
    attr_reader :transition

    sig { params(business: Business, transition: T.nilable(Licensing::LicensingModelTransition)).void }
    def initialize(business:, transition: nil)
      @business = business
      @transition = transition
    end

    sig { returns(T::Boolean) }
    memoize def can_transition_to_volume?
      (!business.metered_plan? && business.advanced_security_metered_for_entity?) || false
    end
  end
end
