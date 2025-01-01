# typed: strict
# frozen_string_literal: true

require "gh/domain/collection"

module GH
  module Domain
    class CursorCollection < GH::Domain::Collection
      Elem = type_member { { upper: BasicObject } }

      sig do
        params(
          members: T::Array[Elem],
          has_previous_page: T::Boolean,
          has_next_page: T::Boolean,
          lazy_total_entries: T.nilable(T.proc.returns(Integer)),
          lazy_cursor: T.nilable(T.proc.params(arg0: T.untyped).returns(T.nilable(String)))
        ).void
      end
      def initialize(
        members:,
        has_previous_page:,
        has_next_page:,
        lazy_total_entries:,
        lazy_cursor:
      )
        @has_previous_page = has_previous_page
        @has_next_page = has_next_page
        @lazy_total_entries = lazy_total_entries
        @lazy_cursor = lazy_cursor

        super(members)
      end

      # start GraphQL::Pagination::Connection interface
      sig { returns(T::Boolean) }
      def has_next_page?
        @has_next_page
      end

      sig { returns(T::Boolean) }
      def has_previous_page?
        @has_previous_page
      end

      sig { returns(Integer) }
      def total_entries
        GitHub::DomainIsolation.within_domain_of(@package) do
          @lazy_total_entries&.call
        end
      end

      sig { params(item: Elem).returns(T.nilable(String)) }
      def cursor_for(item)
        @lazy_cursor&.call(item)
      end

      sig { returns(T.nilable(String)) }
      def start_cursor
        return nil if collection_members.empty?
        cursor_for(T.must(collection_members.first))
      end

      sig { returns(T.nilable(String)) }
      def end_cursor
        return nil if collection_members.empty?
        cursor_for(T.must(collection_members.last))
      end
      # end GraphQL::Pagination::Connection interface
    end
  end
end
