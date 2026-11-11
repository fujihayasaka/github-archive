# frozen_string_literal: true
#              


require "vexi/entity"
require "vexi/actor_collection"
require "vexi/hash_actor_collection"

module Vexi
  DEFAULT_SEGMENT_PREFIX = "_"

  # Segment represents a segment.
  class Segment

    include Entity

    attr_writer :name
    attr_accessor :actors

    def initialize(name, actors: HashActorCollection.new({}), not_found: false)
      @name =      (name        )
      @actors =      (actors                 )
      @not_found =      (not_found            )
    end

    def name
      @name
    end

    def self.create_default(name)
      Segment.new(name)
    end

    def any_actor_enabled?(actor_ids)
      actors.any_actor_enabled?(actor_ids)
    end

    def self.from_hash(h)
      # Warning: Changes to this method will require a reflected change in to_hash and must be made in a backwards
      # compatible way to avoid breaking changes in cached segments.
      Segment.new(
        h["name"].to_s,
        actors: ActorCollection.from_base(h["actors"]),
        not_found: h["not_found"] == true
      )
    end

    def to_hash
      # Warning: Changes to this method will require a reflected change in from_hash and must be made in a backwards
      # compatible way to avoid breaking changes in cached segments.
      {
        "name" => self.name,
        "actors" => self.actors.to_base,
        "not_found" => self.not_found,
      }
    end

    def ==(other)
      return false unless other.is_a?(Segment)
      name == other.name &&
        actors == other.actors &&
        not_found == other.not_found
    end
  end
end
