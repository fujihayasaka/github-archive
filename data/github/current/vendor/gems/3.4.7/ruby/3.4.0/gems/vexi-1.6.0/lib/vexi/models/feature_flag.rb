# frozen_string_literal: true
#              


require "json"
require "vexi/entity"
require "vexi/actor_collection"
require "vexi/array_actor_collection.rb"
require "vexi/hash_actor_collection"

module Vexi
  # FeatureFlag is the struct that represents a feature flag.
  class FeatureFlag

    include Entity

    attr_writer :name
    attr_accessor :boolean_gate
    attr_accessor :percentage_of_actors
    attr_accessor :percentage_of_calls
    attr_accessor :segments
    attr_accessor :custom_gates
    attr_accessor :actors

    def initialize(
      name,
      boolean_gate: false,
      percentage_of_actors: 0.0,
      percentage_of_calls: 0.0,
      segments: [],
      custom_gates: [],
      actors: HashActorCollection.new({})
    )
      @name =      (name        )
      @boolean_gate =      (boolean_gate            )
      @percentage_of_actors =      (percentage_of_actors       )
      @percentage_of_calls =      (percentage_of_calls       )
      @segments =      (segments                  )
      @custom_gates =      (custom_gates                  )
      @actors =      (actors                 )
    end

    def name
      @name
    end

    def self.create_default(name)
      create_boolean_feature_flag(name, false)
    end

    def self.create_boolean_feature_flag(name, enabled)
      FeatureFlag.new(name, boolean_gate: enabled)
    end

    def self.from_hash(h)
      # Warning: Changes to this method will require a reflected change in to_hash and must be made in a backwards
      # compatible way to avoid breaking changes in cached feature flags.
      FeatureFlag.new(
        h["name"].to_s,
        boolean_gate: h["boolean_gate"] == true,
        percentage_of_actors: h["percentage_of_actors"].to_f,
        percentage_of_calls: h["percentage_of_calls"].to_f,
        segments: h["segments"] || [],
        custom_gates: h["custom_gates"] || [],
        actors: ActorCollection.from_base(h["actors"]),
      )
    end

    def to_hash
      # Warning: Changes to this method will require a reflected change in from_hash and must be made in a backwards
      # compatible way to avoid breaking changes in cached feature flags.
      {
        "name" => self.name,
        "boolean_gate" => self.boolean_gate,
        "percentage_of_actors" => self.percentage_of_actors,
        "percentage_of_calls" => self.percentage_of_calls,
        "custom_gates" => self.custom_gates,
        "actors" => self.actors.to_base,
        "segments" => self.segments,
      }
    end

    def ==(other)
      return false unless other.is_a?(FeatureFlag)
      name == other.name &&
        boolean_gate == other.boolean_gate &&
        percentage_of_actors == other.percentage_of_actors &&
        percentage_of_calls == other.percentage_of_calls &&
        segments == other.segments &&
        custom_gates == other.custom_gates &&
        actors == other.actors
    end
  end
end
