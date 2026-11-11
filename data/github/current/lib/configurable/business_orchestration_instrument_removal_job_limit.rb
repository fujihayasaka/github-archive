# typed: true
# frozen_string_literal: true

# Configurable for the limit of concurrent BusinessOrchestrationInstrumentRemovalJob instances
module Configurable
  module BusinessOrchestrationInstrumentRemovalJobLimit
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "business_orchestration_instrument_removal_job_limit"
    DEFAULT_BUSINESS_ORCHESTRATION_INSTRUMENT_REMOVAL_JOB_LIMIT = GitHub.enterprise? ? 3 : 5

    # Get the limit for concurrent BusinessOrchestrationInstrumentRemovalJob instances.
    #
    # Returns Integer.
    sig { returns(Integer) }
    def business_orchestration_instrument_removal_job_limit
      config.get(KEY)&.to_i || DEFAULT_BUSINESS_ORCHESTRATION_INSTRUMENT_REMOVAL_JOB_LIMIT
    end

    # Set the limit for concurrent BusinessOrchestrationInstrumentRemovalJob instances.
    #
    # value - Integer representing the job limit to set.
    # actor - User setting the limit.
    # final - Optional Boolean representing whether the limit should override
    #   values set on objects lower down in the hierarchy.
    #
    # Returns nothing.
    sig { params(value: Integer, actor: User, final: T::Boolean).void }
    def set_business_orchestration_instrument_removal_job_limit(value, actor:, final: false)
      config.set!(KEY, value, actor, final)
    end

    # Clear the limit for concurrent BusinessOrchestrationInstrumentRemovalJob instances.
    #
    # actor: User clearing the limit.
    #
    # Returns nothing.
    sig { params(actor: User).void }
    def clear_business_orchestration_instrument_removal_job_limit(actor:)
      config.delete(KEY, actor)
    end
  end
end
