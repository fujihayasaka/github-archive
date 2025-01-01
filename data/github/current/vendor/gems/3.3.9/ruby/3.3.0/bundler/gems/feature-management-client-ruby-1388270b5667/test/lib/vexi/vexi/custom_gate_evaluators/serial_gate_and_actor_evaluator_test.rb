# frozen_string_literal: true
# typed: true

require "test_helper"
require "testing/test_actor"
require "vexi/custom_gates_evaluators/serial_gate_and_actor_evaluator"

class SerialGateAndActorEvaluatorTest < Minitest::Test
  def setup
    @feature_flag = "feature_flag"

    @custom_gate_funcs = {
      "false_gate" => proc { |_feature_flag, _actor| false },
      "test_actor_gate" => proc { |feature_flag, actor| actor == "test_actor" && !feature_flag.empty? },
      "exception_gate" => proc { |_feature_flag, _actor| raise "error" },
      "check_feature_flag" => proc { |feature_flag, _actor| feature_flag == @feature_flag },
      "actor_gate" => proc { |_feature_flag, actor| actor.is_a?(Vexi::Actor) && actor.vexi_id == "test_actor" }
    }
    @custom_gates_evaluator = Vexi::CustomGatesEvaluators::SerialGateAndActorEvaluator.new(@custom_gate_funcs)
  end

  # test_enabled_true test scenario where the custom gate evaluates to true
  def test_enabled_true
    assert @custom_gates_evaluator.enabled?(@feature_flag, %w[test_actor_gate], %w[test_actor])
    assert @custom_gates_evaluator.enabled?(@feature_flag, %w[test_actor_gate false_gate], %w[test_actor])
    assert @custom_gates_evaluator.enabled?(@feature_flag, %w[false_gate test_actor_gate], %w[test_actor])
    assert @custom_gates_evaluator.enabled?(@feature_flag, %w[test_actor_gate false_gate], %w[test_actor other_actor])
    assert @custom_gates_evaluator.enabled?(@feature_flag, %w[false_gate test_actor_gate], %w[other_actor test_actor])
    assert @custom_gates_evaluator.enabled?(@feature_flag, %w[actor_gate], [TestActor.new("test_actor")])
  end

  # test_enabled_false test scenario where the custom gate evaluates to false
  def test_enabled_false
    refute @custom_gates_evaluator.enabled?(@feature_flag, %w[false_gate], %w[test_actor])
    refute @custom_gates_evaluator.enabled?(@feature_flag, %w[false_gate], %w[test_actor other_actor])
    refute @custom_gates_evaluator.enabled?(@feature_flag, %w[false_gate], %w[other_actor test_actor])
    refute @custom_gates_evaluator.enabled?(@feature_flag, %w[false_gate], %w[])
    refute @custom_gates_evaluator.enabled?(@feature_flag, %w[], %w[test_actor])
    refute @custom_gates_evaluator.enabled?(@feature_flag, %w[], %w[])
    refute @custom_gates_evaluator.enabled?(@feature_flag, %w[false_gate test_actor_gate], %w[other_actor])
    refute @custom_gates_evaluator.enabled?("", %w[test_actor_gate], %w[test_actor])
    refute @custom_gates_evaluator.enabled?(@feature_flag, %w[actor_gate], [TestActor.new("test_actors")])
  end

  # test_enabled_with_exception test scenario where the custom gate evaluation raises an exception
  def test_enabled_with_exception
    refute @custom_gates_evaluator.enabled?(@feature_flag, %w[exception_gate], %w[test_actor])
    refute @custom_gates_evaluator.enabled?(@feature_flag, %w[exception_gate], %w[test_actor other_actor])
    assert @custom_gates_evaluator.enabled?(@feature_flag, %w[exception_gate test_actor_gate], %w[test_actor])
    assert @custom_gates_evaluator.enabled?(@feature_flag, %w[exception_gate test_actor_gate],
                                            %w[test_actor other_actor])
    assert @custom_gates_evaluator.enabled?(@feature_flag, %w[test_actor_gate exception_gate], %w[test_actor])
    refute @custom_gates_evaluator.enabled?(@feature_flag, %w[exception_gate false_gate], %w[test_actor])
  end

  # test_check_feature_flag test scenario where the custom gate checks the feature name
  def test_check_feature_flag
    assert @custom_gates_evaluator.enabled?(@feature_flag, %w[check_feature_flag], %w[test_actor])
    refute @custom_gates_evaluator.enabled?("fake_feature_flag", %w[check_feature_flag], %w[test_actor])
  end

  # test_submit_timing_notification test scenario where timing information is submitted via notifications
  def test_submit_timing_notification
    Vexi::Notifications
    .expects(:instrument_duration)
    .with(
      "serial_gate_and_actor_evaluator.is_enabled_for_custom_gate",
      anything,
      anything,
      {
        feature_flag: "feature_flag", custom_gate_name: "check_feature_flag", result: true,
      }
    )

    assert @custom_gates_evaluator.enabled?(@feature_flag, %w[check_feature_flag], %w[test_actor])
  end

  # test_submit_exception_notification test scenario where an exception is submitted via notifications
  def test_submit_exception_notification
    Vexi::Notifications
    .expects(:instrument_error)
    .with(
      "serial_gate_and_actor_evaluator.is_enabled",
      anything,
      message: "evaluation of custom gate failed",
      context: { feature_flag: @feature_flag, custom_gate_names: ["exception_gate"] },
    )

    refute @custom_gates_evaluator.enabled?(@feature_flag, %w[exception_gate], %w[test_actor])
  end

  def test_name
    assert_equal "serial_gate_and_actor_evaluator", @custom_gates_evaluator.custom_gates_evaluator_name
  end
end
