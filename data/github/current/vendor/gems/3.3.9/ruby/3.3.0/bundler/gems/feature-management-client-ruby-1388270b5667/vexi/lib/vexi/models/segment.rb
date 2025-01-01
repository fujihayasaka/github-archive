# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"
require "vexi/entity"
require "vexi/actor_collection"
require "vexi/hash_actor_collection"

module Vexi
  # Segment represents a segment.
  class Segment

    include Entity

    attr_writer :name
    attr_accessor :actors

    def initialize(name, actors: HashActorCollection.new({}))
      @name = T.let(name, String)
      @actors = T.let(actors, ActorCollection)
    end

    def name
      @name
    end

    def self.create_default(name)
      Segment.new(name)
    end

    def self.from_hash(h)
      # Warning: Changes to this method will require a reflected change in to_hash and must be made in a backwards
      # compatible way to avoid breaking changes in cached segments.
      Segment.new(
        h["name"].to_s,
        actors: ActorCollection.from_base(h["actors"]),
      )
    end

    def to_hash
      # Warning: Changes to this method will require a reflected change in from_hash and must be made in a backwards
      # compatible way to avoid breaking changes in cached segments.
      {
        "name" => self.name,
        "actors" => self.actors.to_base
      }
    end

    def ==(other)
      return false unless other.is_a?(Segment)
      name == other.name &&
        actors == other.actors
    end
  end
end
