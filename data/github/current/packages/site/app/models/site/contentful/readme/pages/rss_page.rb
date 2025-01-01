# typed: true
# frozen_string_literal: true

class Site::Contentful::Readme::Pages::RssPage < Site::Contentful::Page
  def cache_key
    "site.contentful.readme.pages.rss/v1"
  end

  def fetch_data_from_contentful
    developer_stories = Site::Contentful::Readme::DeveloperStory.all(include_unpublished: false, limit: 10, **Site::Contentful::Readme::BaseStory.select_for_rss_feed)
    featured_articles = Site::Contentful::Readme::FeaturedArticle.all(include_unpublished: false, limit: 10, **Site::Contentful::Readme::BaseStory.select_for_rss_feed)
    guides = Site::Contentful::Readme::Guide.all(include_unpublished: false, limit: 10, **Site::Contentful::Readme::BaseStory.select_for_rss_feed)

    sorted_stories = [developer_stories, featured_articles, guides].flatten(1).sort_by(&:publication_date).reverse

    {
      stories: sorted_stories.map(&:to_json)
    }
  end
end
