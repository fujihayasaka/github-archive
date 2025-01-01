# typed: true
# frozen_string_literal: true

module DiscussionSpotlightsHelper
  def discussion_spotlight_gradient_background_style(color_stops)
    color1, color2 = color_stops
    gradient_style = "linear-gradient(to right, ##{color1}, ##{color2})"
    "background-image: #{gradient_style}"
  end
end
