# frozen_string_literal: true
# typed: strict

module Vexi
  # FeatureFlag is the struct that represents a feature flag.
  class FeatureFlag
    extend T::Sig
    extend T::Helpers

    include Entity

    sig { params(name: String).void }
    attr_writer :name

    sig { returns(T::Boolean) }
    attr_accessor :boolean_gate

    sig { returns(Float) }
    attr_accessor :percentage_of_actors

    sig { returns(Float) }
    attr_accessor :percentage_of_calls

    sig { returns(T::Array[String]) }
    attr_accessor :segments

    sig { returns(T::Array[String]) }
    attr_accessor :custom_gates

    sig { returns(ActorCollection) }
    attr_accessor :actors

    sig do
      params(
        name: String,
        boolean_gate: T::Boolean,
        percentage_of_actors: Float,
        percentage_of_calls: Float,
        segments: T::Array[String],
        custom_gates: T::Array[String],
        actors: ActorCollection
      ).void
    end
    def initialize(
      name,
      boolean_gate: false,
      percentage_of_actors: 0.0,
      percentage_of_calls: 0.0,
      segments: [],
      custom_gates: [],
      actors: HashActorCollection.new({})
    ); end

    sig { override.returns(String) }
    def name; end

    sig { params(name: String).returns(FeatureFlag) }
    def self.create_default(name); end

    sig { params(name: String, enabled: T::Boolean).returns(FeatureFlag) }
    def self.create_boolean_feature_flag(name, enabled); end

    sig { params(h: T::Hash[String, T.untyped]).returns(FeatureFlag) }
    def self.from_hash(h); end

    sig { returns(T::Hash[String, T.untyped]) }
    def to_hash; end

    sig { params(feature_flag: FeatureFlag).returns(Integer) }
    def self.calculate_state(feature_flag); end

    sig { params(state: T.untyped).returns(Integer) }
    def self.resolve_state(state); end

    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other); end
  end
end
