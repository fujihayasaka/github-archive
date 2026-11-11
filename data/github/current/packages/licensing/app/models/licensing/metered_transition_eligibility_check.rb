# typed: true
# frozen_string_literal: true

module Licensing
  # Represents a single eligibility criterion for self-serve metered transition.
  # Used to provide detailed feedback to stafftools users about why a business
  # is or isn't eligible for the V->M transition.
  class MeteredTransitionEligibilityCheck
    sig { returns(String) }
    attr_reader :name, :description

    sig { returns(T::Boolean) }
    attr_reader :passed

    sig { params(name: String, description: String, passed: T::Boolean).void }
    def initialize(name:, description:, passed:)
      @name = name
      @description = description
      @passed = passed
    end

    sig { returns(T::Boolean) }
    def failed?
      !passed
    end
  end
end
