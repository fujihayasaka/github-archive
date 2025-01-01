# typed: true
# frozen_string_literal: true

class Site::Contentful::CustomerStories::Pages::CustomerStoryShowPage < Site::Contentful::Page
  def initialize(story_slug:, for_staff: false)
    @slug = story_slug
    @for_staff = for_staff
  end

  def cache_key
    "site.swp.customer_stories.story.#{@slug}.staff:#{@for_staff}"
  end

  def fetch_data_from_contentful
    customer_story = Site::Contentful::CustomerStories::CustomerStory.find(@slug, include_preview: @for_staff)

    return { customer_story: nil } if customer_story.blank?

    { customer_story: customer_story.to_json }
  end
end
