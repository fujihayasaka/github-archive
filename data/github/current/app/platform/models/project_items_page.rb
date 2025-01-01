# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectItemsPage
  attr_reader :items, :page_info, :total_count

  def initialize(items:, page_info: nil, total_count:)
    @items = items
    @page_info = page_info
    @total_count = total_count
  end
end
