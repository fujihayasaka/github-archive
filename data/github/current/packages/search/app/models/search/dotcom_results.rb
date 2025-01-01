# typed: true
# frozen_string_literal: true

module Search
  class DotcomResults
    include Enumerable

    # Creates a new, empty search results. This is handy to use after an error
    # has occurred but you still want a results object.
    def self.empty
      new({ "total_count" => 0, "items" => [] }, page: 1)
    end

    def self.timed_out
      new({ "total_count" => 0, "timed_out" => true, "items" => [] }, page: 1)
    end

    attr_reader :total, :page, :per_page, :max_offset, :timed_out
    attr_accessor :results
    delegate :each, to: :results

    # Create a new Dotcom Results collection from the dotcom API response.
    # The response is a raw JSON document
    #
    # response - The response Hash returned from Dotcom API.
    # opts     - Optional arguments Hash for pagination.
    #   :page     - The current page number.
    #   :per_page - The number of results per page.
    #
    def initialize(response, opts = {})
      @total   = response["total_count"].to_i
      @results = response["items"]
      @timed_out = response["timed_out"] || false

      @page       = opts.fetch(:page, nil)
      @per_page   = opts.fetch(:per_page, ::Search::Query::per_page_default)
      @max_offset = opts.fetch(:max_offset, ::Search::Query::max_offset_default)
    end

    def empty?
      @total == 0
    end

    def timed_out?
      @timed_out
    end

    def size
      results.size
    end
    alias :length :size

    # Here be will_paginate compatibility
    alias :total_entries :total

    def current_page
      pagination_enabled!
      page
    end

    # Assert that we have a page number
    def pagination_enabled!
      return unless page.nil?
      raise ArgumentError,
        "Pagination is not available when `page` is not passed to Search::DotcomResults.new."
    end

    # Returns the total number of pages available for these search results.
    #
    # The total number of search results that will ever be returned is
    # capped. The farther you offset into a set of search results, the more
    # work the search index has to do. This adversely affects performance;
    # hence it is capped.
    def total_pages
      pagination_enabled!
      max_pages   = (max_offset / per_page.to_f).ceil
      total_pages = (total / per_page.to_f).ceil
      (total_pages < max_pages) ? total_pages : max_pages
    end

    # Returns the previous page number of nil if there is no previous page.
    def previous_page
      pagination_enabled!
      current_page > 1 ? (current_page - 1) : nil
    end

    # Returns the next page number of nil if there is no next page.
    def next_page
      pagination_enabled!
      current_page < total_pages ? (current_page + 1) : nil
    end

    # The current offset into the actual search results.
    def offset
      pagination_enabled!
      per_page * (current_page - 1)
    end

    # Returns true if the current page is greater than the total number of pages.
    def out_of_bounds?
      pagination_enabled!
      current_page > total_pages
    end
  end
end
