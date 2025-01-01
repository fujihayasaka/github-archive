# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"
require "vexi/actor_collection"

module Vexi

  class HashActorCollection
    include Vexi::ActorCollection

    attr_reader :actors_hash

    def initialize(actors_hash)
      @actors_hash = T.let(actors_hash, T::Hash[String, T::Boolean])
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

    def delete(key); end

    def keys
      @actors_hash.keys
    end

    def length
      @actors_hash.length
    end

    def values
      @actors_hash.values
    end

    def inspect
      "#{self.class.name}(#{@actors_hash.inspect})"
    end

    def ==(obj)
      return false unless obj.is_a?(HashActorCollection)

      obj.actors_hash == @actors_hash
    end

    def to_base
      @actors_hash
    end
  end
end
