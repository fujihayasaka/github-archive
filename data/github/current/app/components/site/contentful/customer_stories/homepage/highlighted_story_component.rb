# typed: true
# frozen_string_literal: true

class Site::Contentful::CustomerStories::Homepage::HighlightedStoryComponent < ApplicationComponent
  include SvgHelper

  def initialize(story)
    @story = story
  end

  def render?
    @story.present?
  end
end
