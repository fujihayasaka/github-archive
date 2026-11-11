# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class Location # rubocop:disable ViewComponent/ComponentsHaveUnitTests
    attr_reader :start_line, :end_line, :start_column, :end_column

    def initialize(start_line, end_line, start_column, end_column)
      @start_line = start_line
      @end_line = end_line
      @start_column = start_column
      @end_column = end_column
    end
  end
end
