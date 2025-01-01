# typed: strict
# frozen_string_literal: true

module FeatureManagement
  module Management
    class Node
      extend T::Sig

      NODE_INVALID = "INVALID"
      NODE_DISABLED = "DISABLED"
      NODE_PARTIALLY_SHIPPED = "PARTIALLY_SHIPPED"
      NODE_SHIPPED = "SHIPPED"

      sig { returns(String) }
      attr_accessor :name

      sig { returns(String) }
      attr_accessor :state

      sig { returns(T.nilable(String)) }
      attr_accessor :parent

      sig { returns(PercentageOfCalls) }
      attr_accessor :percentage_of_calls

      sig { returns(PercentageOfActors) }
      attr_accessor :percentage_of_actors

      sig { returns(CustomGates) }
      attr_accessor :custom_gates

      sig { params(name: String, state: String, parent: T.nilable(String)).void }
      def initialize(name, state, parent)
        @name = T.let(name, String)
        @state = T.let(state, String)
        @parent = T.let(parent, T.nilable(String))
        @percentage_of_calls = T.let(PercentageOfCalls.new(false, 0.0), PercentageOfCalls)
        @percentage_of_actors = T.let(PercentageOfActors.new(false, 0.0), PercentageOfActors)
        @custom_gates = T.let(CustomGates.new(false, []), CustomGates)
      end
    end
  end
end
