# frozen_string_literal: true
#              


require "zlib"

module Vexi
  # Public: Vexi custom gates evaluator interface.
  class NonActorGateEvaluator

    def self.evaluate_boolean_gate(feature_flag)
      feature_flag.boolean_gate
    end

    def self.evaluate_percentage_of_calls(feature_flag)
      return false if feature_flag.percentage_of_calls.zero?
      return true if feature_flag.percentage_of_calls == 100

      Random.rand < (feature_flag.percentage_of_calls / 100.0)
    end

    # Private: this constant is used to support up to 3 decimal places in percentages.
    SCALING_FACTOR = 1_000

    def self.evaluate_percentage_of_actors(feature_flag, actor_ids)
      return false if feature_flag.percentage_of_actors.zero?
      return false if actor_ids.empty?
      return true if feature_flag.percentage_of_actors == 100

      id = feature_flag.name + actor_ids.sort.join

      Zlib.crc32(id) % (100 * SCALING_FACTOR) < feature_flag.percentage_of_actors * SCALING_FACTOR
    end

    def self.evaluate_embedded_actors(embedded_actor_ids, actor_ids)
      return false if actor_ids.empty?

      actor_ids.any? do |actor|
        embedded_actor_ids[actor]
      end
    end
  end
end
