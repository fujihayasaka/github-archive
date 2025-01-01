# frozen_string_literal: true
# typed: strict

module Vexi
  module Adapters
    class ArrayActorCollection
      extend T::Sig
      extend T::Helpers

      include ::Vexi::ActorCollection

      sig { returns(T::Array[String]) }
      attr_reader :actors_array

      sig { params(actors_array: T::Array[String]).void }
      def initialize(actors_array); end

      sig { override.params(key: String).returns(T.nilable(T::Boolean)) }
      def [](key); end

      sig { override.params(key: String, value: T::Boolean).void }
      def []=(key, value); end

      sig do
        override
        .params(
          blk: T.proc.params(elem: [String, T::Boolean]).returns(BasicObject)
        ).void
      end
      def each(&blk); end

      sig { override.params(key: String).void }
      def delete(key); end

      sig { override.returns(T::Array[String]) }
      def keys; end

      sig { override.returns(Numeric) }
      def length; end

      sig { override.returns(T::Array[T::Boolean]) }
      def values; end

      sig { override.returns(String) }
      def inspect; end

      sig { override.params(obj: T.untyped).returns(T::Boolean) }
      def ==(obj); end

      sig { override.returns(T::Array[String]) }
      def to_base; end
    end
  end
end
