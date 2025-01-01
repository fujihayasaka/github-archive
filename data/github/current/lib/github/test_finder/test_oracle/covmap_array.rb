# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module GitHub
  module TestFinder
    # Array for in-memory storage of (path, *targets) pairs.
    # This will be used for sigle transaction appends to the DB,
    # instead of previous approach where every append! results in write operation
    class CovmapArray
      extend T::Sig
      def initialize
        @covmap = T.let([], T::Array[T::Hash[String, String]])
      end

      sig { params(tuple: T::Array[String]).void }
      def <<(tuple)
        covmap << { tuple[0] => tuple[1] }
      end

      sig { returns(T::Array[T::Hash[String, String]]) }
      def covmap
        @covmap
      end
    end # CovmapArray
  end # Coverage
end # GitHub
