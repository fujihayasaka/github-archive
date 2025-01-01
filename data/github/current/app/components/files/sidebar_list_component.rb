# typed: true
# frozen_string_literal: true

module Files
  class SidebarListComponent < ApplicationComponent
    MAX_COUNT = 3

    include DeploymentsHelper

    def initialize(title:, href:, count: 0, max_count: MAX_COUNT, **args)
      @title, @href, @count, @max_count, @args = title, href, count, max_count, args
    end

    def items_to_show
      if @count < @max_count
        @count
      elsif @count == @max_count + 1
        @max_count + 1
      else
        @max_count
      end
    end

    private

    def more_items?
      @count > @max_count + 1
    end
  end
end
