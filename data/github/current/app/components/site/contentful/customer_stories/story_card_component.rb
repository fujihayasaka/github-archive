# typed: true
# frozen_string_literal: true

class Site::Contentful::CustomerStories::StoryCardComponent < ApplicationComponent
  include SvgHelper, Site::CustomerStoriesHelper

  def initialize(story)
    # Since we are still working on making all pages for the customer-stories project work with cache-friendly data,
    # this component needs to be able to work with both Contentful::Entry instances and JSON-like hashes.
    @story = if story.is_a?(Site::Contentful::CustomerStories::CustomerStory)
      story.preview_json
    else
      story
    end
  end
end
