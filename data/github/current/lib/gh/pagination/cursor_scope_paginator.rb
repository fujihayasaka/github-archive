# typed: strict
# frozen_string_literal: true

module GH
  module Pagination
    class CursorScopePaginator
      extend T::Generic
      extend T::Helpers

      Elem = type_member { { upper: BasicObject } }

      sig do
        params(
          scope: ActiveRecord::Relation,
          pagination: GH::Pagination::Cursor,
          lazy_total_entries: T.nilable(T.proc.returns(Integer))
        ).void
      end
      def initialize(scope:, pagination:, lazy_total_entries: nil)
        @scope = scope
        @pagination = pagination
        @lazy_total_entries = lazy_total_entries
      end

      sig { returns(GH::Domain::CursorCollection[Elem]) }
      def paginate
        connection_wrapper = Platform::ConnectionWrappers::Relation.new(scope, **pagination.to_hash)
        connection_wrapper.set_security_violation_behaviour(:allow) if self.pagination.disable_auth
        members = connection_wrapper.edge_nodes.sync.to_a
        page_info = connection_wrapper.page_info
        lazy_cursor = -> (member) { connection_wrapper.cursor_for(member).sync }

        GH::Domain::CursorCollection.new(
          members:,
          has_next_page: page_info.has_next_page?,
          has_previous_page: page_info.has_previous_page?,
          lazy_cursor: lazy_cursor,
          lazy_total_entries: lazy_total_entries || -> { connection_wrapper.total_count }
        )
      end

      sig { returns(Integer) }
      def total_entries
        lazy_total_entries&.call || scope.count
      end

      private

      sig { returns(ActiveRecord::Relation) }
      attr_reader :scope

      sig { returns(GH::Pagination::Cursor) }
      attr_reader :pagination

      sig { returns(T.nilable(T.proc.returns(Integer))) }
      attr_reader :lazy_total_entries
    end
  end
end
