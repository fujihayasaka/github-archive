# frozen_string_literal: true
# typed: strict

module Vexi
  # Public: Vexi Custom Gates evaluators that ship with the library.
  module CustomGatesEvaluators
    # Public: Serially evaluates each custom gate for each actor id or actor individually.
    # Does not support batching actors to a custom gate.
    class SerialGateAndActorEvaluator
      extend T::Sig
      extend T::Helpers

      include CustomGatesEvaluator

      sig do
        params(
          custom_gate_funcs: T::Hash[String, T.proc.params(feature_flag: String, actor: T.any(Actor, String)
        ).returns(T::Boolean)]).void
      end
      def initialize(custom_gate_funcs); end

      sig do
        override.params(
          feature_flag: String, custom_gate_names: T::Array[String], actors: T::Array[T.any(Actor, String)],
        ).returns(T::Boolean)
      end
      def enabled?(feature_flag, custom_gate_names, actors); end

      sig { override.returns String }
      def custom_gates_evaluator_name; end
    end
  end
end
