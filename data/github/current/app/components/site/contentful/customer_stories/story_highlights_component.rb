# typed: true
# frozen_string_literal: true

class Site::Contentful::CustomerStories::StoryHighlightsComponent < ApplicationComponent
  ALLOWED_HIGHLIGHT_NAMES = %w[Problem Solution].freeze

  def initialize(highlights: [], classes: nil, dark: false, large_names: false, products: [], icon_size: :small)
    @highlights = highlights
    @classes = classes
    @dark = dark
    @large_names = large_names
    @icon_size = icon_size
    # Note: products parameter is kept for backward compatibility but no longer used
  end

  def render?
    @highlights.any? { |highlight| ALLOWED_HIGHLIGHT_NAMES.include?(highlight[:name]) }
  end
end
