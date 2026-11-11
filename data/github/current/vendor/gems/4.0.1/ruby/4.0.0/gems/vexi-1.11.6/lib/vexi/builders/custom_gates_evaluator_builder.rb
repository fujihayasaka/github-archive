# frozen_string_literal: true
#              

require "vexi/configuration"
require "vexi/custom_gates_evaluators/serial_gate_and_actor_evaluator"

module Vexi
  module Builders
    class CustomGatesEvaluatorBuilder
      def initialize(config)
        @config =      (config               )
      end

      def serial_gate_and_actor_evaluator(custom_gate_funcs)
        @config.custom_gates_evaluator = CustomGatesEvaluators::SerialGateAndActorEvaluator.new(custom_gate_funcs)
      end

      def custom(custom_gates_evaluator)
        @config.custom_gates_evaluator = custom_gates_evaluator
      end
    end
  end
end
