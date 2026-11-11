# typed: true
# frozen_string_literal: true

class Site::Contentful::Readme::Pages::FeaturedArticles::ShowPage < Site::Contentful::Page
  include Site::Contentful::Readme::Pages::Fetchers::MoreStoriesFetcher
  include Site::Contentful::Readme::Pages::Fetchers::NavigationTopicsFetcher

  def initialize(story_slug:, for_readme_staff: false)
    @story_slug = story_slug
    @for_readme_staff = for_readme_staff
  end

  sig { override.returns(Site::Contentful::Page::CacheKey) }
  def cache_key
    Site::Contentful::Page::CacheKey.new(
      base: "site.swp.readme.featured_articles",
      path: @story_slug,
      user_provided_parameters: { staff: @for_readme_staff.to_s },
    )
  end

  sig { override.params(new_data: JsonLikeType).returns(T::Boolean) }
  def content_found?(new_data)
    new_data[:story].present?
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    story = Site::Contentful::Readme::FeaturedArticle.find(@story_slug, include_unpublished: @for_readme_staff)

    if story.blank?
      return {
        story: nil,
        contributing: nil,
        has_approved_sponsors_account: nil,
        more_stories: nil,
        navigation_topics: [],
      }
    end

    {
      has_approved_sponsors_account: story.has_approved_sponsors_account?,
      more_stories: fetch_more_stories_for(story).map(&:to_json),
      navigation_topics: fetch_navigation_topics.map(&:to_json),
      story: story.to_json,
    }
  end
end
