# typed: true
# frozen_string_literal: true

module TaskLists
  class SummaryView
    attr_accessor :summary

    def initialize(summary = nil)
      @summary = summary
    end

    delegate :item_count, :complete_count, :incomplete_count, to: :summary

    def text
      "#{item_count} tasks (#{complete_count} completed, #{incomplete_count} remaining)"
    end
  end
end
