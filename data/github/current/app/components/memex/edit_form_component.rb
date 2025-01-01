# typed: true
# frozen_string_literal: true

module Memex
  class EditFormComponent < ApplicationComponent
    attr_reader :memex, :item, :readonly

    def initialize(memex:, item:, viewer_can_write:)
      @memex = memex
      @item = item
      @readonly = !viewer_can_write || item.archived?
    end

    def columns
      return @columns if defined?(@columns)

      @columns = memex.columns.select { |c| c.user_defined }

      @column_values = item
        .column_values(columns: @columns, require_prefilled_associations: false)
        .filter { |v| v[:value] }
        .map { |v| [v[:memexProjectColumnId], v[:value]] }
        .to_h

      @columns
    end
  end
end
