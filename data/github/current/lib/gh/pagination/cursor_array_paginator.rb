# typed: strict
# frozen_string_literal: true

module GH
  module Pagination
    class CursorArrayPaginator
      extend T::Generic
      extend T::Helpers

      Elem = type_member { { upper: BasicObject } }

      sig do
        params(
          array: T::Array[Elem],
          pagination: GH::Pagination::Cursor,
          lazy_total_entries: T.nilable(T.proc.returns(Integer))
        ).void
      end
      def initialize(array:, pagination:, lazy_total_entries: nil)
        @array = array
        @pagination = pagination
        @lazy_total_entries = lazy_total_entries
      end

      sig { returns(GH::Domain::CursorCollection[Elem]) }
      def paginate
        before = pagination.before
        after = pagination.after
        first = pagination.first
        last = pagination.last

        sliced_array = if before && after
          array[index_from_cursor(after)..index_from_cursor(before) - 1] || []
        elsif before
          array[0..index_from_cursor(before) - 2] || []
        elsif after
          array[index_from_cursor(after)..-1] || []
        else
          array
        end

        has_previous_page = if last
          sliced_array.count > last
        elsif after
          index_from_cursor(after) > 0
        else
          false
        end

        has_next_page = if first
          sliced_array.count > first
        elsif before
          index_from_cursor(before) < array.length + 1
        else
          false
        end

        limited_array = sliced_array
        limited_array = limited_array.first(first) if first
        limited_array = limited_array.last(last) if last

        GH::Domain::CursorCollection.new(
          members: limited_array,
          has_next_page: has_next_page,
          has_previous_page: has_previous_page,
          lazy_cursor: -> (member) { cursor_from_index(T.must(array.find_index(member)) + 1) },
          lazy_total_entries: lazy_total_entries || -> { array.count }
        )
      end

      sig { returns(Integer) }
      def total_entries
        lazy_total_entries&.call || array.count
      end

      private

      sig { returns(T::Array[Elem]) }
      attr_reader :array

      sig { returns(GH::Pagination::Cursor) }
      attr_reader :pagination

      sig { returns(T.nilable(T.proc.returns(Integer))) }
      attr_reader :lazy_total_entries

      sig { params(cursor: String).returns(Integer) }
      def index_from_cursor(cursor)
        Base64.urlsafe_decode64(cursor).to_i
      end

      sig { params(idx: Integer).returns(String) }
      def cursor_from_index(idx)
        Base64.urlsafe_encode64(idx.to_s, padding: false)
      end
    end
  end
end
