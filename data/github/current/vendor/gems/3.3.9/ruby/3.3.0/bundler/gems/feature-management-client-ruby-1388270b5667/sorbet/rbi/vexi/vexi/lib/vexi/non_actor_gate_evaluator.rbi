# frozen_string_literal: true
# typed: strict

module Vexi
  # Public: Vexi custom gates evaluator interface.
  class NonActorGateEvaluator
    extend T::Sig
    extend T::Helpers

    sig { params(feature_flag: FeatureFlag).returns(T::Boolean) }
    def self.evaluate_boolean_gate(feature_flag); end

    sig { params(feature_flag: FeatureFlag).returns(T::Boolean) }
    def self.evaluate_percentage_of_calls(feature_flag); end

    private_constant :SCALING_FACTOR

    sig { params(feature_flag: FeatureFlag, actor_ids: T::Array[String]).returns(T::Boolean) }
    def self.evaluate_percentage_of_actors(feature_flag, actor_ids); end

    sig { params(embedded_actor_ids: ActorCollection, actor_ids: T::Array[String]).returns(T::Boolean) }
    def self.evaluate_embedded_actors(embedded_actor_ids, actor_ids); end
  end
end
