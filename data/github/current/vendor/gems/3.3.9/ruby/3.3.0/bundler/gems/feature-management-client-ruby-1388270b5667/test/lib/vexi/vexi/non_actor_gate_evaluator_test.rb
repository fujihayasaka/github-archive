# frozen_string_literal: true
# typed: true

require "test_helper"

class NonActorGateEvaluatorTest < Minitest::Test
  def test_evaluate_boolean_gate_returns_true_if_boolean_gate_true
    feature_flag = Vexi::FeatureFlag.create_boolean_feature_flag("feature", true)
    assert_equal true, Vexi::NonActorGateEvaluator.evaluate_boolean_gate(feature_flag)
  end

  def test_evaluate_boolean_gate_returns_false_if_boolean_gate_false
    feature_flag = Vexi::FeatureFlag.create_boolean_feature_flag("feature", false)
    assert_equal false, Vexi::NonActorGateEvaluator.evaluate_boolean_gate(feature_flag)
  end

  def test_evaluate_percentage_of_calls_returns_false_if_percentage_of_calls_zero
    feature = Vexi::FeatureFlag.new("feature", percentage_of_calls: 0.0)
    assert_equal false, Vexi::NonActorGateEvaluator.evaluate_percentage_of_calls(feature)
  end

  def test_evaluate_percentage_of_calls_returns_true_if_percentage_of_calls_100
    feature = Vexi::FeatureFlag.new("feature", percentage_of_calls: 100.0)
    assert_equal true, Vexi::NonActorGateEvaluator.evaluate_percentage_of_calls(feature)
  end

  def test_evaluate_percentage_of_calls_returns_true_if_random_number_less_than_percentage_of_calls
    feature = Vexi::FeatureFlag.new("feature", percentage_of_calls: 50.0)

    Random.stub :rand, 0.49 do
      assert_equal true, Vexi::NonActorGateEvaluator.evaluate_percentage_of_calls(feature)
    end
  end

  def test_evaluate_percentage_of_calls_returns_false_if_random_number_greater_than_percentage_of_calls
    feature = Vexi::FeatureFlag.new("feature", percentage_of_calls: 50.0)

    Random.stub :rand, 0.51 do
      assert_equal false, Vexi::NonActorGateEvaluator.evaluate_percentage_of_calls(feature)
    end
  end

  def test_evaluate_percentage_of_actors_returns_false_if_actor_ids_empty
    feature = Vexi::FeatureFlag.new("feature")
    assert_equal false, Vexi::NonActorGateEvaluator.evaluate_percentage_of_actors(feature, [])
  end

  def test_evaluate_percentage_of_actors_returns_false_if_percentage_of_actors_zero
    feature = Vexi::FeatureFlag.new("feature", percentage_of_actors: 0.0)
    assert_equal false, Vexi::NonActorGateEvaluator.evaluate_percentage_of_actors(feature, ["actor"])
  end

  def test_evaluate_percentage_of_actors_returns_false_if_percentage_of_actors_100_and_actor_ids_empty
    feature = Vexi::FeatureFlag.new("feature", percentage_of_actors: 100.0)
    assert_equal false, Vexi::NonActorGateEvaluator.evaluate_percentage_of_actors(feature, [])
  end

  def test_evaluate_percentage_of_actors_returns_true_if_percentage_of_actors_100
    feature = Vexi::FeatureFlag.new("feature", percentage_of_actors: 100.0)
    assert_equal true, Vexi::NonActorGateEvaluator.evaluate_percentage_of_actors(feature, ["actor"])
  end

  def test_evaluate_percentage_of_actors_returns_false_if_crc32_id_greater_than_percentage_of_actors
    feature = Vexi::FeatureFlag.new("feature", percentage_of_actors: 50.0)

    # 1,266,360,001 makes the evaluation become 60,0001 < 50 * 1000
    Zlib.stub :crc32, 1_266_360_001 do
      assert_equal false, Vexi::NonActorGateEvaluator.evaluate_percentage_of_actors(feature, ["actor"])
    end
  end

  def test_evaluate_percentage_of_actors_returns_true_if_crc32_id_less_than_percentage_of_actors
    feature = Vexi::FeatureFlag.new("feature", percentage_of_actors: 50.0)

    # 1,824,745,163 makes the evaluation become 45,163 > 50 * 1000
    Zlib.stub :crc32, 1_824_745_163 do
      assert_equal true, Vexi::NonActorGateEvaluator.evaluate_percentage_of_actors(feature, ["actor"])
    end
  end

  def test_evaluate_embedded_actors_returns_false_if_actor_ids_empty
    assert_equal false, Vexi::NonActorGateEvaluator.evaluate_embedded_actors(Vexi::HashActorCollection.new({}), [])
  end

  def test_evaluate_embedded_actors_returns_false_if_embedded_actor_ids_empty
    assert_equal false, Vexi::NonActorGateEvaluator.evaluate_embedded_actors(Vexi::HashActorCollection.new({}), ["actor"])
  end

  def test_evaluate_embedded_actors_returns_true_if_embedded_actor_ids_include_actor
    embedded_actor_ids = Vexi::HashActorCollection.new({ "actor" => true })
    assert_equal true, Vexi::NonActorGateEvaluator.evaluate_embedded_actors(embedded_actor_ids, ["actor"])
  end

  def test_evaluate_embedded_actors_returns_false_if_embedded_actor_ids_does_not_include_actor
    embedded_actor_ids = Vexi::HashActorCollection.new({ "actor" => false })
    assert_equal false, Vexi::NonActorGateEvaluator.evaluate_embedded_actors(embedded_actor_ids, ["actor"])
  end

  # Test evaluate_embedded_actors works with embedded actor ids and multiple actor ids
  def test_evaluate_embedded_actors_returns_true_if_embedded_actor_ids_include_any_actor
    embedded_actor_ids = Vexi::HashActorCollection.new({ "actor" => true, "actor-2" => true })
    assert_equal true, Vexi::NonActorGateEvaluator.evaluate_embedded_actors(embedded_actor_ids, %w[actor other])
  end
end
