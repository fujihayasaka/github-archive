# frozen_string_literal: true
#              


require "vexi/actor_collection"

module Vexi
  module Adapters
    class ArrayActorCollection
      include ::Vexi::ActorCollection

      attr_reader :actors_array

      def initialize(actors_array)
        @actors_array =      (actors_array                  )
      end

      def [](key)
        # Binary search for the actor in the actors_array
        @actors_array.bsearch { |actor|
          comparison_result = key <=> actor

          if !comparison_result
            raise TypeError, "Unable to compare #{key} with #{actor}"
          end

          comparison_result
        } == key
      end

      def []=(key, value)
        raise NotImplementedError
      end

      def each(&blk)
        actors_array.each { |actor| blk.call([actor, true]) }
      end

      def delete(key)
        raise NotImplementedError
      end

      def keys
        @actors_array
      end

      def length
        @actors_array.length
      end

      def values
        @actors_array.each.map { |actor| true }
      end

      def inspect
        "#{self.class.name}(#{@actors_array.inspect})"
      end

      def ==(obj)
        return false unless obj.is_a?(ArrayActorCollection)

        obj.actors_array == @actors_array
      end

      def to_base
        @actors_array
      end
    end
  end
end
