# typed: strict
# frozen_string_literal: true

module OctoCore
  module Context
    class Stash
      extend T::Sig
      extend Forwardable

      sig { void }
      def initialize
        @stash = T.let({}, T::Hash[Symbol, T.untyped])
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        @stash
      end

      sig { params(key_values: T::Hash[Symbol, T.untyped], block: T.proc.void).void }
      def push(key_values, &block)
        old_stash = @stash
        @stash = @stash.merge(key_values)
        yield
      ensure
        @stash = T.must(old_stash)
      end

      def_delegators :@stash, :[], :[]=
    end
  end
end
