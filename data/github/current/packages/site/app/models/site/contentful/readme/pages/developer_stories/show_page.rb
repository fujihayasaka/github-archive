# typed: true
# frozen_string_literal: true

class Site::Contentful::Readme::Pages::DeveloperStories::ShowPage < Site::Contentful::Page
  include Site::Contentful::Readme::Pages::Fetchers::MoreStoriesFetcher
  include Site::Contentful::Readme::Pages::Fetchers::NavigationTopicsFetcher

  def initialize(story_slug:, for_readme_staff: false)
    @story_slug = story_slug
    @for_readme_staff = for_readme_staff
  end

  def cache_key
    "site.contentful.readme.pages.developer_stories.show.#{@story_slug}.for_readme_staff:#{@for_readme_staff}/v1"
  end

  def fetch_data_from_contentful
    story = Site::Contentful::Readme::DeveloperStory.find(@story_slug, include_unpublished: @for_readme_staff)

    return { story: nil, contributing: nil, more_stories: nil, navigation_topics: [] } if story.blank?

    {
      contributing: story.contributing,
      more_stories: fetch_more_stories_for(story).map(&:to_json),
      navigation_topics: fetch_navigation_topics.map(&:to_json),
      story: story.to_json,
    }
  end
end
