# frozen_string_literal: true
#              


require "vexi/actor_collection"

module Vexi

  class HashActorCollection < ActorCollection

    attr_reader :actors_hash

    def initialize(actors_hash)
      @actors_hash =      (actors_hash                             )
    end

    def [](key)
      @actors_hash[key]
    end

    def []=(key, value)
      @actors_hash[key] = value
    end

    def each(&blk)
      @actors_hash.each(&blk)
    end

    def delete(key)
      @actors_hash.delete(key)
    end

    def keys
      @actors_hash.keys
    end

    def values
      @actors_hash.values
    end

    def ==(obj)
      return false unless obj.is_a?(HashActorCollection)

      obj.actors_hash == @actors_hash
    end

    def to_a
      @actors_hash.select { |_, value| value }.keys
    end

    def to_base
      @actors_hash
    end
  end
end
