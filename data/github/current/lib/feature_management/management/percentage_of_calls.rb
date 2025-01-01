# typed: strict
# frozen_string_literal: true

module FeatureManagement
  module Management
    class PercentageOfCalls
      sig { returns(T::Boolean) }
      attr_accessor :enabled

      sig { returns(T.any(Integer, Float)) }
      attr_accessor :value

      sig { params(enabled: T::Boolean, value: T.any(Integer, Float)).void }
      def initialize(enabled, value)
        @enabled = T.let(enabled, T::Boolean)
        @value = T.let(value, T.any(Integer, Float))
      end
    end
  end
end
