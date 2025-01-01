# typed: true
# frozen_string_literal: true

module Newsies
  # Represents a page of data returned by a method in the public Newsies
  # interface defined by Newsies::Service.
  class PageWithPreviousAndNextFlags
    attr_accessor :page, :has_next_page, :has_previous_page

    def initialize(page: [], has_next_page: false, has_previous_page: false)
      @page = page
      @has_next_page = has_next_page
      @has_previous_page = has_previous_page
    end
  end
end
