# typed: false
# frozen_string_literal: true

require "will_paginate"

module GitHub
  module SimplePagination
    def self.paginate_collection(collection, per_page: WillPaginate.per_page, page: 1, initial_per_page: nil)
      PaginationWrapper
        .new(collection)
        .simple_paginate(per_page: per_page, page: page, initial_per_page: initial_per_page)
    end

    # Public: Simple pagination alternative to WillPaginate when the total
    # number of pages doesn't need to be displayed. For an example, the
    # simple_paginate view helper only outputs Next and Previous buttons with
    # individual page links.
    #
    # per_page - Integer number of items per page (default: 30)
    # page - Integer page number starting at 1 (default: 1)
    # initial_per_page - Integer number representing the per_page count of the
    #                    first page. This is useful in cases where we show a small
    #                    number of items on the first page but more for subsequent
    #                    pages.
    #
    # Returns a SimplePagination::Collection.
    def simple_paginate(per_page: WillPaginate.per_page, page: 1, initial_per_page: nil)
      page = 1 if page.nil? || page < 1

      limit  = per_page + 1

      if initial_per_page && page > 1
        offset = initial_per_page + (page - 2) * per_page
      else
        offset = (page - 1) * per_page
      end

      results = limit(limit).offset(offset).to_a
      total = offset + results.size
      has_more = results.size > per_page

      collection = Collection.new(page: page, per_page: per_page, has_more: has_more)

      # Pop off extra result if we're over the page limit
      results.pop if has_more
      collection.replace(results)

      collection
    end

    # Quacks somewhat like a WillPaginate::Collection, but doesn't know
    # `total_entries` nor `total_pages` count.
    class Collection < Array
      attr_reader :current_page, :per_page

      def initialize(page:, per_page:, has_more: false)
        @current_page = page
        @per_page = per_page
        @has_more = has_more
      end

      def previous_page
        current_page - 1 if has_previous_page?
      end

      def next_page
        current_page + 1 if has_more?
      end

      def has_more?
        @has_more
      end

      def has_previous_page?
        current_page > 1
      end
    end

    class PaginationWrapper
      include GitHub::SimplePagination

      def initialize(collection)
        @original_collection = collection
      end

      def limit(n)
        @limit = n
        self
      end

      def offset(n)
        @offset = n
        self
      end

      def to_a
        @original_collection.drop(@offset).take(@limit)
      end
    end
  end
end
