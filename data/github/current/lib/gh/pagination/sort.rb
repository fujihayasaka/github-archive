# typed: strict
# frozen_string_literal: true

module GH
  module Pagination
    class Sort
      class Direction < T::Enum
        enums do
          ASC = new("ASC")
          DESC = new("DESC")
        end

        sig { params(str: T.nilable(String)).returns(Direction) }
        def self.from_string(str)
          (
            GH::Pagination::Sort::Direction.try_deserialize(str&.upcase) ||
            GH::Pagination::Sort::Direction::ASC
          )
        end
      end

      sig { returns(String) }
      attr_reader :field
      sig { returns(Direction) }
      attr_reader :direction

      sig { params(field: String, direction: Direction).void }
      def initialize(field:, direction:)
        @field = T.let(field, String)
        @direction = T.let(direction, Direction)
      end

      sig { params(sorts: T::Array[GH::Pagination::Sort]).returns(String) }
      def self.to_order_by(sorts:)
        sorts.map { |sort| "#{sort.field} #{sort.direction.serialize}" }.join(", ")
      end

      sig { params(scope: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def sort(scope:)
        scope.order("? ?", field, direction.serialize)
      end
    end
  end
end
