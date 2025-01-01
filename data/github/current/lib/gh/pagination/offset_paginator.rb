# typed: strict
# frozen_string_literal: true

module GH
  module Pagination
    class OffsetPaginator
      extend T::Generic
      extend T::Helpers

      Elem = type_member { { upper: BasicObject } }

      sig do
        params(
          scope: ActiveRecord::Relation,
          pagination: GH::Pagination::Offset,
          sorts: T.nilable(T::Array[GH::Pagination::Sort]),
          lazy_total_entries: T.nilable(T.proc.returns(Integer))
        ).void
      end
      def initialize(scope:, pagination:, sorts:, lazy_total_entries: nil)
        @scope = scope
        @pagination = pagination
        @sorts = sorts
        @lazy_total_entries = lazy_total_entries
      end

      sig { returns(GH::Domain::OffsetCollection[Elem]) }
      def paginate
        scope = T.unsafe(self.scope).paginate({ per_page: pagination.per_page, page: pagination.page })
        scope = scope.unscope(:order).order(GH::Pagination::Sort.to_order_by(sorts: T.must(sorts))) if sorts
        members = WillPaginate::Collection.create(pagination.page, pagination.per_page) do |col|
          col.replace(scope)
          col.total_entries = 0
        end

        GH::Domain::OffsetCollection.new(
          members:,
          current_page: pagination.page,
          per_page: pagination.per_page,
          lazy_total_entries: lazy_total_entries || -> { scope.unscope(:order).unscope(:select).count }
        )
      end

      sig { returns(GH::Domain::OffsetCollection[Elem]) }
      def subquery_paginate
        subquery_scope = self.scope
          .reselect(:id)
          .paginate({ per_page: pagination.per_page, page: pagination.page })
        subquery_scope = subquery_scope.unscope(:order).order(GH::Pagination::Sort.to_order_by(sorts: T.must(sorts))) if sorts
        subquery = subquery_scope.to_sql

        members_scope = T.unsafe(scope)
          .unscoped
          .joins("INNER JOIN (#{subquery}) AS subquery ON `#{T.unsafe(scope).table_name}`.id = subquery.id")
        members_scope = members_scope.order(GH::Pagination::Sort.to_order_by(sorts: T.must(sorts))) if sorts
        members = WillPaginate::Collection.create(pagination.page, pagination.per_page) do |col|
          col.replace(members_scope)
          col.total_entries = 0
        end

        GH::Domain::OffsetCollection.new(
          members:,
          current_page: pagination.page,
          per_page: pagination.per_page,
          lazy_total_entries: lazy_total_entries || -> { scope.unscope(:order).unscope(:select).count }
        )
      end

      private

      sig { returns(ActiveRecord::Relation) }
      attr_reader :scope

      sig { returns(GH::Pagination::Offset) }
      attr_reader :pagination

      sig { returns(T.nilable(T::Array[GH::Pagination::Sort])) }
      attr_reader :sorts

      sig { returns(T.nilable(T.proc.returns(Integer))) }
      attr_reader :lazy_total_entries
    end
  end
end
