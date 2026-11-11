# typed: true
# frozen_string_literal: true

module Platform
  class StableArrayWrapper < Array
    DEFAULT_SORT_BY_PROC = -> (item) { [item.created_at, item.id] }

    attr_writer :sort_by_proc
    def sort_by_proc
      return @sort_by_proc if defined?(@sort_by_proc)
      @sort_by_proc = DEFAULT_SORT_BY_PROC
    end
  end
end
