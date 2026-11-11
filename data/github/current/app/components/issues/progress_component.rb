# typed: true
# frozen_string_literal: true

module Issues
  class ProgressComponent < ApplicationComponent

    SIZES = [:big, :small, :inline].freeze

    def initialize(size:, percent: 0, style: "", color: nil, border_color: nil, include_fill: false)
      @size = fetch_or_fallback(SIZES, size, :small)
      @percent = percent.to_f
      @circumference = (2 * Math::PI * radius).round
      @style = style
      @color = color || "var(--fgColor-accent, var(--color-accent-fg))"
      @border_color = border_color || "var(--bgColor-accent-muted, var(--color-accent-subtle))"
      @include_fill = include_fill
    end

    def render?
      @percent.between?(0, 100)
    end

    def radius
      (size - stroke_width) / 2
    end

    def size
      @size == :small ? 12 : 16
    end

    def stroke_width
      @size == :small ? 2 : 3
    end

    def stroke_rotate
      cap_radius = stroke_width.fdiv(2)
      cap_radius.fdiv(circumference).fdiv(2) * 360
    end

    def circumference
      @circumference
    end

    def offset
      if @percent < 100
        (100 - @percent).fdiv(100) * @circumference + stroke_width.fdiv(2)
      else
        0
      end
    end

    def fill_path
      offset = size / 2
      start_x, start_y = get_coordinates_for_percent(0)
      end_x, end_y = get_coordinates_for_percent(@percent)
      large_arc_flag = @percent > 50 ? 1 : 0

      "M #{start_x + offset} #{start_y + offset} A #{radius} #{radius} 0 #{large_arc_flag} 1 #{end_x + offset} #{end_y + offset} L #{offset} #{offset}"
    end

    def get_coordinates_for_percent(percent)
      x = Math.cos(2 * Math::PI * percent.fdiv(100)) * radius
      y = Math.sin(2 * Math::PI * percent.fdiv(100)) * radius
      [x, y]
    end
  end
end
