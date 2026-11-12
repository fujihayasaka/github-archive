# typed: strict
# frozen_string_literal: true

module OctoCore
  module Pagination

    # A module that provides a way to iterate through pages of a collection of items:
    #
    #  iter = OctoCore::Pagination::Iterator.new(pagination) do |page|
    #    Things.domain.fetch_page(page)
    #  end
    #
    #  iter.each_page do |page|
    #    page.each do |item|
    #      puts item
    #    end
    #  end
    #
    class Iterator
      extend T::Sig
      extend T::Generic

      Elem = type_member { { upper: BasicObject } }

      # Create a new iterator. USE CAUTION: This uses default bounds checking for subsequent pages. DEPRECATED for offset paginations.
      # Needs to be replaced with Cursor paginations ONLY.
      #
      # pagination - Describes the starting page of the iteration.
      # fetch_block - A block that fetches a page of items from the collection, according to the provided pagination.
      sig { params(pagination: Offset, fetch_block: T.proc.params(pagination: Offset).returns(T::Enumerable[Elem])).void }
      def initialize(pagination, &fetch_block)
        @pagination = pagination
        @fetch_block = fetch_block
      end

      # Iterate through each page of the collection.
      # The provided block will be called with each page of items.
      sig { params(block: T.proc.params(items: T::Enumerable[Elem]).void).void }
      def each_page(&block)
        current_pagination = @pagination

        items = @fetch_block.call(@pagination)

        while items.any?
          yield items
          current_pagination = Offset.build(page: current_pagination.page + 1, per_page: current_pagination.per_page)
          items = @fetch_block.call(current_pagination)
        end
      end
    end
  end
end
