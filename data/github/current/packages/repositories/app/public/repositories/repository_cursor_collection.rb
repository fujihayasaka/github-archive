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
      ).void
    end
    def initialize(
      collection:,
      pagination:
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

      super(
        members: [],
        has_previous_page: false,
        has_next_page: false,
        lazy_total_entries: nil,
        lazy_cursor: nil
      )
    end

    sig do
      override.params(
        blk: T.proc.params(arg0: Elem).returns(BasicObject),
      ).returns(T::Array[Elem])
    end
    def each(&blk)
      paginated_collection.each { |member| yield member }
    end

    sig { returns(Integer) }
    memoize def total_disk_usage
      case collection
      when ActiveRecord::Relation
        collection.sum(:disk_usage)
      when Array
        collection.sum(&:disk_usage)
      end
    end

    private

    sig { returns(GH::Domain::CursorCollection[Elem]) }
    memoize def paginated_collection
      GitHub::DomainIsolation.within_domain_of(package) do
        collection = paginator.paginate
        @has_next_page = collection.has_next_page?
        @has_previous_page = collection.has_previous_page?
        @lazy_cursor = ->(member) { collection.cursor_for(member) }
        @lazy_total_entries = -> { collection.total_entries }
        collection
      end
    end

    sig { returns(T.any(ActiveRecord::Relation, T::Array[Elem])) }
    attr_reader :collection

    sig { returns(T.nilable(T.proc.returns(Integer))) }
    attr_reader :lazy_total_entries

    sig { returns(T.any(GH::Pagination::CursorScopePaginator[Elem], GH::Pagination::CursorArrayPaginator[Elem])) }
    attr_reader :paginator
  end
end
