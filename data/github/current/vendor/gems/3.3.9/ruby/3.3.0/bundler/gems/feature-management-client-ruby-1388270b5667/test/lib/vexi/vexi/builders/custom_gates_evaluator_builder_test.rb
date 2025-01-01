# frozen_string_literal: true
# typed: true

require "test_helper"
require "faraday"

require "vexi/builders/custom_gates_evaluator_builder"
require "vexi/configuration"

class CacheBuilderTest < Minitest::Test
  class TestCustomGatesEvaluator
    include Vexi::CustomGatesEvaluator

    def custom_gates_evaluator_name; "test_custom_gates_evaluator" end
    def enabled?(feature_name, custom_gate_names, actors); end
  end

  def setup
    @config = Vexi::Configuration.new
    @custom_gates_evaluator_builder = Vexi::Builders::CustomGatesEvaluatorBuilder.new(@config)
  end

  def test_in_memory
    @custom_gates_evaluator_builder.serial_gate_and_actor_evaluator({})

    assert_equal(@config.custom_gates_evaluator.custom_gates_evaluator_name, "serial_gate_and_actor_evaluator")
  end

  def test_custom
    custom_evaluator = TestCustomGatesEvaluator.new

    @custom_gates_evaluator_builder.custom(custom_evaluator)

    assert_equal(custom_evaluator, @config.custom_gates_evaluator)
  end
end
