# typed: true
# frozen_string_literal: true

class SlashCommands::ColumnsComponent < ApplicationComponent
  COLUMN_SIZES = {
    1 => [12],
    2 => [6, 6],
    3 => [4, 4, 4],
    4 => [3, 3, 3],
    5 => [3, 3, 2, 2, 2],
    6 => [2, 2, 2, 2, 2, 2]
  }

  class Column
    attr_reader :component, :padding, :size
    def initialize(component, padding:, size:)
      @component = component
      @padding = padding
      @size = size
    end

    def css_classes
      "col-#{size} #{padding}"
    end
  end

  attr_reader :components
  def initialize(components)
    @components = components

    if components.length > 6
      raise ArgumentError.new("You provided too many components (supports up to six)")
    elsif components.length.zero?
      raise ArgumentError.new("You must provide at least one component (supports up to six)")
    end
  end

  def number_of_components
    components.length
  end

  def columns
    COLUMN_SIZES[number_of_components].each_with_index.map do |size, index|
      component = components[index]
      padding = if index.zero?
        "pr-1"
      elsif index == (number_of_components - 1)
        "pl-1"
      else
        "pr-1 pl-1"
      end

      Column.new(component, size: size, padding: padding)
    end
  end
end
