# typed: false
# frozen_string_literal: true

module DonutHelper
  def donut_svg(values, outer_radius = 15, inner_radius = 9)
    diameter = outer_radius * 2

    sum = values.sum { |_, value| value }.to_f

    cx = cy = diameter / 2
    pi = Math::PI

    scale = lambda { |value, radius|
      radians = value / sum * pi * 2 - pi / 2
      [radius * Math.cos(radians) + cx, radius * Math.sin(radians) + cy]
    }

    cumulative = 0

    paths = []

    values.each do |name, value|
      value = value.to_f
      portion = value / sum
      next if portion == 0

      if portion == 1
        x2 = cx - 0.01
        y1 = cy - outer_radius
        y2 = cy - inner_radius

        d  = ["M", cx, y1]
        d += ["A", outer_radius, outer_radius, 0, 1, 1, x2, y1]
        d += ["L", x2, y2]
        d += ["A", inner_radius, inner_radius, 0, 1, 0, cx, y2]

        paths << content_tag(:path, "", d: d.join(" "), class: name)
      else
        cumulative_plus_value = cumulative + value

        d  = ["M"] + scale.call(cumulative, outer_radius)
        d += ["A", outer_radius, outer_radius, 0]
        d += [portion > 0.5 ? 1 : 0]
        d += [1]
        d += scale.call(cumulative_plus_value, outer_radius)
        d += ["L"]

        d += scale.call(cumulative_plus_value, inner_radius)
        d += ["A", inner_radius, inner_radius, 0]
        d += [portion > 0.5 ? 1 : 0]
        d += [0]
        d += scale.call(cumulative, inner_radius)

        cumulative += value

        paths << content_tag(:path, "", d: d.join(" "), class: name)
      end
    end

    content_tag :svg, safe_join(paths), height: diameter, width: diameter, class: "donut-chart"
  end
end
