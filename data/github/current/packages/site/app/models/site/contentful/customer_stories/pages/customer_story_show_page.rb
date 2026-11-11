# typed: true
# frozen_string_literal: true

class Site::Contentful::CustomerStories::Pages::CustomerStoryShowPage < Site::Contentful::Page
  def initialize(story_slug:, for_staff: false)
    @slug = story_slug
    @for_staff = for_staff
  end

  sig { override.returns(Site::Contentful::Page::CacheKey) }
  def cache_key
    Site::Contentful::Page::CacheKey.new(
      base: "site.swp.customer_stories.story",
      path: @slug,
      user_provided_parameters: { staff: @for_staff.to_s },
    )
  end

  sig { override.params(new_data: JsonLikeType).returns(T::Boolean) }
  def content_found?(new_data)
    new_data[:customer_story].present?
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    customer_story = Site::Contentful::CustomerStories::CustomerStory.find(@slug, include_preview: @for_staff)

    return { customer_story: nil } if customer_story.blank?

    { customer_story: customer_story.to_json }
  end
end
