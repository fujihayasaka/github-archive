# typed: strict
# frozen_string_literal: true

# Whether a customer (enterprise account or org) has become eligible for GitHub Advanced Security
module Configurable
  module AdvancedSecurityEligibility
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { ActiveRecord::Base }

    ADVANCED_SECURITY_ELIGIBILITY_KEY = "advanced_security_eligibility"

    sig { params(actor: User).returns(T::Boolean) }
    def enable_advanced_security_eligiblity_for_entity(actor:)
      config.enable(ADVANCED_SECURITY_ELIGIBILITY_KEY, actor)
    end

    sig { params(actor: User).returns(T::Boolean) }
    def disable_advanced_security_eligibility_for_entity(actor:)
      config.delete(ADVANCED_SECURITY_ELIGIBILITY_KEY, actor)
    end

    sig { returns(T::Boolean) }
    def advanced_security_eligible_for_entity?
      return false if new_record?
      return false unless config.local?(ADVANCED_SECURITY_ELIGIBILITY_KEY)

      config.enabled?(ADVANCED_SECURITY_ELIGIBILITY_KEY)
    end
  end
end
