# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class PaginatedResult
      extend T::Generic

      Elem = type_member

      sig { returns(Elem) }
      attr_reader :data

      sig { returns(T.nilable(String)) }
      attr_reader :next_cursor, :previous_cursor

      sig { params(data: Elem, next_cursor: T.nilable(String), previous_cursor: T.nilable(String)).void }
      def initialize(data:, next_cursor:, previous_cursor:)
        @data = data
        @next_cursor = next_cursor
        @previous_cursor = previous_cursor
      end
    end
  end
end
