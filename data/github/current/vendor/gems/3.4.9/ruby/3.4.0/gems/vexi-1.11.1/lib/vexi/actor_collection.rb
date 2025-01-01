# frozen_string_literal: true
#              

module Vexi
  # Public: Abstract base class for actor collections
  class ActorCollection
    extend T::Sig
    extend T::Helpers

    include Enumerable

    # Check if any of the provided actor IDs are enabled in this collection
    def any_actor_enabled?(actor_ids)
      return false if actor_ids.empty?

      actor_ids.any? do |actor|
        self[actor]
      end
    end

    # Abstract methods that must be implemented by subclasses
    def each(&blk)
      raise NotImplementedError, "Subclasses must implement #each"
    end

    def [](key)
      raise NotImplementedError, "Subclasses must implement #[]"
    end

    def []=(key, value)
      raise NotImplementedError, "Subclasses must implement #[]="
    end

    def delete(key)
      raise NotImplementedError, "Subclasses must implement #delete"
    end

    def keys
      raise NotImplementedError, "Subclasses must implement #keys"
    end

    def values
      raise NotImplementedError, "Subclasses must implement #values"
    end

    def length
      keys.length
    end

    def empty?
      keys.empty?
    end

    # Returns the base object that this collection wraps. This is used for serialization.
    def to_base
      raise NotImplementedError, "Subclasses must implement #to_base"
    end

    def to_a
      raise NotImplementedError, "Subclasses must implement #to_a"
    end

    def inspect
      "#{self.class.name}(#{to_base.inspect})"
    end

    def self.from_base(base)
      if base.is_a?(Hash)
        HashActorCollection.new(base)
      elsif base.is_a?(Array)
        ArrayActorCollection.new(base)
      else
        # Unknown type of actors, default to empty HashActorCollection
        HashActorCollection.new({})
      end
    end
  end
end
