# typed: true
# frozen_string_literal: true

module SlashCommands
  class DialogComponent < ApplicationComponent
    attr_reader :breadcrumbs, :min_width, :max_width, :max_height

    renders_one :footer

    def initialize(breadcrumbs: [], min_width: nil, max_width: nil, max_height: 300)
      @breadcrumbs = breadcrumbs
      @min_width = min_width
      @max_width = max_width
      @max_height = max_height
    end

    def min_width_style
      "min-width: #{min_width}px;" if min_width.present?
    end

    def max_width_style
      "max-width: #{max_width}px;" if max_width.present?
    end

    def max_height_style
      "max-height: #{max_height}px;" if max_height.present?
    end
  end
end
