# typed: true
# frozen_string_literal: true

module Stafftools
  class PaginatedCollection < WillPaginate::Collection
    def self.create(old_collection, new_array)
      current_page  = old_collection.current_page
      per_page      = old_collection.per_page
      total_entries = old_collection.total_entries

      super(current_page, per_page, total_entries) do |pager|
        pager.replace new_array
      end
    end
  end
end
