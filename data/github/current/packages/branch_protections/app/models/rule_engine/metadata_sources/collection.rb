# typed: strict
# frozen_string_literal: true

module RuleEngine
  module MetadataSources
    class Collection
      extend T::Sig
      extend T::Generic

      Item = type_member { { upper: Types::Candidate } }

      sig { returns(T::Array[Item]) }
      attr_reader :items

      sig { returns(T.nilable(String)) }
      attr_reader :next_cursor

      sig { params(items: T::Array[Item], next_cursor: T.nilable(String)).void }
      def initialize(items, next_cursor)
        @items = items
        @next_cursor = next_cursor
      end

      sig { returns(T::Boolean) }
      def has_more?
        !@next_cursor.nil?
      end
    end
  end
end
