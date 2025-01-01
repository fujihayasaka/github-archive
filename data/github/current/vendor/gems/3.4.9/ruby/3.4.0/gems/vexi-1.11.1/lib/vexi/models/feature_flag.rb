# frozen_string_literal: true
#              


require "json"
require "zlib"
require "vexi/entity"
require "vexi/actor_collection"
require "vexi/array_actor_collection.rb"
require "vexi/hash_actor_collection"

module Vexi
  # FeatureFlag is the struct that represents a feature flag.
  class FeatureFlag
    include Entity

    # Private: this constant is used to support up to 3 decimal places in percentages.
    SCALING_FACTOR = 1_000
    FULLY_ENABLED_PERCENTAGE = 100.0
    FULLY_DISABLED_PERCENTAGE = 0.0

    attr_writer :name
    attr_accessor :boolean_gate
    attr_accessor :percentage_of_actors
    attr_accessor :percentage_of_calls
    attr_accessor :segments
    attr_accessor :custom_gates
    attr_accessor :actors
    attr_accessor :not_found

    def initialize(
      name,
      boolean_gate: false,
      percentage_of_actors: FULLY_DISABLED_PERCENTAGE,
      percentage_of_calls: FULLY_DISABLED_PERCENTAGE,
      segments: [],
      custom_gates: [],
      actors: HashActorCollection.new({}),
      not_found: false
    )
      @name =      (name        )
      @boolean_gate =      (boolean_gate            )
      @percentage_of_actors =      (percentage_of_actors       )
      @percentage_of_calls =      (percentage_of_calls       )
      @segments =      (segments                  )
      @custom_gates =      (custom_gates                  )
      @actors =      (actors                 )
      @not_found =      (not_found            )
    end

    def name
      @name
    end

    def fully_enabled?
      boolean_gate || percentage_of_calls == FULLY_ENABLED_PERCENTAGE
    end

    def fully_disabled?
      return false if boolean_gate
      return false if percentage_of_actors > FULLY_DISABLED_PERCENTAGE
      return false if percentage_of_calls > FULLY_DISABLED_PERCENTAGE
      return false if segments.any?
      return false if custom_gates.any?
      return false if actors.any?

      true
    end

    def self.create_default(name)
      create_boolean_feature_flag(name, false)
    end

    def self.create_boolean_feature_flag(name, enabled)
      FeatureFlag.new(name, boolean_gate: enabled)
    end

    def any_actor_enabled?(actor_ids)
      actors.any_actor_enabled?(actor_ids)
    end

    def boolean_gate_enabled?
      boolean_gate
    end

    def percentage_of_actors_enabled?(actor_ids)
      return false if actor_ids.empty?
      return false if percentage_of_actors.zero?
      return true if percentage_of_actors == FULLY_ENABLED_PERCENTAGE

      id = name + actor_ids.sort.join

      Zlib.crc32(id) % (100 * SCALING_FACTOR) < percentage_of_actors * SCALING_FACTOR
    end

    def percentage_of_calls_enabled?
      return false if percentage_of_calls.zero?
      return true if percentage_of_calls == FULLY_ENABLED_PERCENTAGE

      Random.rand < (percentage_of_calls / 100.0)
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
        not_found: h["not_found"] == true,
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
        "not_found" => self.not_found,
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
        actors == other.actors &&
        not_found == other.not_found
    end
  end
end
