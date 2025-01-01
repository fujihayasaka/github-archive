# typed: true
# frozen_string_literal: true
class Site::Contentful::CustomerStories::StoryPreviewComponent < ApplicationComponent
  include SvgHelper, Site::CustomerStoriesHelper

  def initialize(story)
    @story = story
  end

  def logo
    return @story[:logo][:url] if @story[:logo].present?
  end
end
