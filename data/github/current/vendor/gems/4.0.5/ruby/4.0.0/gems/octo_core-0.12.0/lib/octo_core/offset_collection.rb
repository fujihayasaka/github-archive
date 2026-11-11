# typed: strict
# frozen_string_literal: true

module OctoCore
  # Essentially an interface for WillPaginate::Collection or GitHub::SimplePagination.
  class OffsetCollection
    extend T::Sig
    extend T::Generic
    extend Forwardable

    include OctoCore::Memoizer
    include Enumerable

    #seems generic to me
    Elem = type_member { { upper: BasicObject } }

    def_delegator :@members, :each

    sig do
      params(
        members: T::Array[Elem],
        pagination: OctoCore::Pagination::Offset,
        lazy_total_entries: T.proc.returns(Integer),
      ).void
    end
    def initialize(members:, pagination:, lazy_total_entries:)
      @current_page = T.let(pagination.page, Integer)
      @per_page = T.let(pagination.per_page, Integer)
      @lazy_total_entries = lazy_total_entries
      @members = members
    end

    # begin WillPaginate::Collection interface
    sig { returns(Integer) }
    attr_reader :current_page

    sig { returns(Integer) }
    attr_reader :per_page

    sig { returns(Integer) }
    def total_pages
      total_entries.zero? ? 1 : (total_entries / per_page.to_f).ceil
    end

    sig { returns(Integer) }
    memoize def total_entries
      @lazy_total_entries.call
    end
    # end WillPaginate::Collection interface

    # begin GitHub::SimplePagination interface
    sig { returns(T.nilable(Integer)) }
    def next_page
      current_page + 1 if total_entries > (current_page * per_page)
    end
    # end GitHub::SimplePagination interface
  end
end
