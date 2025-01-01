# typed: strict
# frozen_string_literal: true

require "gh/domain/cursor_collection"

module Repositories
  # This is basically a GH::Domain::CursorCollection but pagination is done at the time the collection is
  # enumerated rather than the collection being passed a pagination list when it's initialized
  class RepositoryCursorCollection < GH::Domain::CursorCollection
    include GitHub::Memoizer

    Elem = type_member { { upper: BasicObject } }

    sig do
      params(
        collection: T.any(ActiveRecord::Relation, T::Array[Elem]),
        pagination: GH::Pagination::Cursor,
        with_members: T::Boolean,
        with_page_info: T::Boolean,
        with_total_count: T::Boolean,
        with_total_disk_usage: T::Boolean,
      ).void
    end
    def initialize(
      collection:,
      pagination:,
      with_members:,
      with_page_info:,
      with_total_count:,
      with_total_disk_usage:
    )
      @collection = collection
      @paginator = T.let(
        case collection
        when ActiveRecord::Relation
          GH::Pagination::CursorScopePaginator.new(scope: collection, pagination:)
        when Array
          GH::Pagination::CursorArrayPaginator.new(array: collection, pagination:)
        end,
        T.any(GH::Pagination::CursorScopePaginator[Elem], GH::Pagination::CursorArrayPaginator[Elem])
      )

      members = []
      has_next_page = false
      has_previous_page = false
      lazy_cursor = nil
      lazy_total_entries = nil
      if with_members || with_page_info
        members = paginated_collection.to_a
        has_next_page = paginated_collection.has_next_page?
        has_previous_page = paginated_collection.has_previous_page?
        lazy_cursor = ->(member) { paginated_collection.cursor_for(member) }
      end
      if with_total_count
        lazy_total_entries = -> { paginator.total_entries }
      end
      if with_total_disk_usage
        @total_disk_usage = T.let(
          case collection
          when ActiveRecord::Relation
            collection.sum(:disk_usage)
          when Array
            T.cast(collection, T::Array[IRepository]).sum(&:disk_usage)
          end,
          Integer
        )
      end

      super(
        members:,
        has_previous_page:,
        has_next_page:,
        lazy_total_entries:,
        lazy_cursor:
      )
    end

    sig { returns(Integer) }
    attr_reader :total_disk_usage

    private

    sig { returns(GH::Domain::CursorCollection[Elem]) }
    memoize def paginated_collection
      GitHub::DomainIsolation.within_domain_of(package) do
        paginator.paginate
      end
    end

    sig { returns(T.any(ActiveRecord::Relation, T::Array[Elem])) }
    attr_reader :collection

    sig { returns(T.any(GH::Pagination::CursorScopePaginator[Elem], GH::Pagination::CursorArrayPaginator[Elem])) }
    attr_reader :paginator

  end
end
