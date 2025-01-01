# typed: strict
# frozen_string_literal: true

require_relative "./cursor_array_paginator"
require_relative "./cursor_scope_paginator"
require_relative "./offset_paginator"

module GH
  module Pagination
    module Paginator
      extend T::Helpers
      extend T::Generic

      Elem = type_template { { upper: BasicObject } }

      sig do
        params(
          scope: ActiveRecord::Relation,
          pagination: GH::Pagination::Base,
          sorts: T.nilable(T::Array[GH::Pagination::Sort]),
          lazy_total_entries: T.nilable(T.proc.returns(Integer)),
          subquery_paginate: T::Boolean
        ).returns(GH::Domain::Collection[Elem])
      end
      def self.paginate(scope:, pagination:, sorts: nil, lazy_total_entries: nil, subquery_paginate: false)
        case pagination
        when GH::Pagination::Offset
          paginator = GH::Pagination::OffsetPaginator[Elem].new(
            scope:,
            pagination:,
            sorts:,
            lazy_total_entries:
          )
          if subquery_paginate
            paginator.subquery_paginate
          else
            paginator.paginate
          end
        when GH::Pagination::Cursor
          GH::Pagination::CursorScopePaginator[Elem].new(
            scope:,
            pagination:,
            lazy_total_entries:
          ).paginate
        else
          raise ArgumentError, "Unknown pagination type: #{pagination.inspect}"
        end
      end

      sig do
        params(
          array: T::Array[Elem],
          pagination: GH::Pagination::Base,
          lazy_total_entries: T.nilable(T.proc.returns(Integer))
        ).returns(GH::Domain::Collection[Elem])
      end
      def self.paginate_array(array:, pagination:, lazy_total_entries: nil)
        case pagination
        when GH::Pagination::Cursor
          GH::Pagination::CursorArrayPaginator[Elem].new(
            array:,
            pagination:,
            lazy_total_entries:
          ).paginate
        else
          raise ArgumentError, "Unknown pagination type: #{pagination.inspect}"
        end
      end
    end
  end
end
