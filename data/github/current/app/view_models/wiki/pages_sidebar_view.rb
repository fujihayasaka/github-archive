# typed: true
# frozen_string_literal: true

class Wiki::PagesSidebarView < Wiki::PagesView
  # Internal: The number of pages to show by default.
  LIMIT = 15

  # Public: Should the pages listing include a filter
  #
  # returns Boolean
  def filter?
    page_count > LIMIT
  end

  # Public: Total number of pages in the wiki
  #
  # Returns Integer
  def page_count
    pages.count
  end

  # Public: Number of pages that are hidden
  #
  # Returns Integer
  def more_count
    filter? ? page_count - LIMIT : 0
  end

  # Public: The pages that are visible by default.
  #
  # Returns Array of GitHub::Unsullied::Page objects
  def initial_pages
    pages.take(LIMIT)
  end

  # Public: The pages that are hidden behind a "Show more" link
  #
  # Returns Array of GitHub::Unsullied::Page objects
  def more_pages
    pages.drop(LIMIT)
  end
end
