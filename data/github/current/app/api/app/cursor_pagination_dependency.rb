# typed: true
# frozen_string_literal: true

module Api::App::CursorPaginationDependency
  # Public: Builds cursor based pagination based on a page info hash
  #
  # page_info  - Hash of page info details.
  # per_page   - The Integer number of maximum results per page
  #
  # Examples
  #
  #   build_cursor_based_links('prev_cursor' => 3, 'next_cursor' => 10, 30)
  #   # => @links
  #
  # Returns @links with the prev and next lings added.
  def build_cursor_based_links(page_info, per_page)
    @links.add_current({ cursor: page_info["next_cursor"], per_page: per_page }, rel: "next") if page_info["next_cursor"]
    @links.add_current({ cursor: page_info["prev_cursor"], per_page: per_page }, rel: "prev") if page_info["prev_cursor"]
  end
end
