# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache
    class Comparison
      extend T::Helpers

      sig { params(diff: T::Array[T::Array[String]]).void }
      def initialize(diff)
        @diff = T.let(diff, T::Array[T::Array[String]])
      end

      sig { returns(T::Array[T::Array[String]]) }
      attr_reader :diff

      sig { returns(T::Boolean) }
      def identical?
        diff.empty?
      end

      sig { returns(T::Array[String]) }
      def mismatches
        return [] if identical?

        diff.map { |d| d[1] }.compact
      end
    end
  end
end
