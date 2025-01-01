# typed: true
# frozen_string_literal: true

module Coders
  class BusinessCoder < Coders::Base
    data_accessors :completed_onboarding_tasks

    sig { returns(T::Array[Symbol]) }
    def completed_onboarding_tasks
      data[:completed_onboarding_tasks]&.map(&:to_sym) || []
    end
  end
end
