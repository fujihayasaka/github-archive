# typed: strict
# frozen_string_literal: true

module FeatureManagement
  module Management
    class CustomGates
      sig { returns(T::Boolean) }
      attr_accessor :enabled

      sig { returns(T::Array[String]) }
      attr_accessor :values

      sig { params(enabled: T::Boolean, values: T::Array[String]).void }
      def initialize(enabled, values)
        @enabled = T.let(enabled, T::Boolean)
        @values = T.let(values, T::Array[String])
      end
    end
  end
end
