# typed: true
# frozen_string_literal: true

class Site::Contentful::Readme::Pages::IndexPage < Site::Contentful::Page
  include Site::Contentful::Readme::Pages::Fetchers::NavigationTopicsFetcher

  def initialize(for_readme_staff: false)
    @for_readme_staff = for_readme_staff
  end

  def cache_key
    "site.contentful.readme.pages.index.for_readme_staff:#{@for_readme_staff}/v1"
  end

  def fetch_data_from_contentful
    homepage = Site::Contentful::Readme::Homepage.latest(include_unpublished: @for_readme_staff)
    homepage_cache_key = Digest::SHA256.hexdigest("#{homepage.id}-#{homepage.updated_at.iso8601}")

    build_cache_key_for_topic = ->(topic) { Digest::SHA256.hexdigest("#{topic.id}-#{topic.updated_at.iso8601}") }

    navigation_topics = fetch_navigation_topics
    navigation_topics_cache_key = navigation_topics.map(&build_cache_key_for_topic).join("/")

    build_cache_key_for_story = ->(story) { Digest::SHA256.hexdigest("#{story.id}-#{story.updated_at.iso8601}") }

    podcasts = fetch_latest_stories(Site::Contentful::Readme::Podcast, homepage: homepage)
    podcasts_cache_key = podcasts.map(&build_cache_key_for_story).join("/")

    guides = fetch_latest_stories(Site::Contentful::Readme::Guide, homepage: homepage)
    guides_cache_key = guides.map(&build_cache_key_for_story).join("/")

    featured_articles = fetch_latest_stories(Site::Contentful::Readme::FeaturedArticle, homepage: homepage)
    featured_articles_cache_key = featured_articles.map(&build_cache_key_for_story).join("/")

    developer_stories = fetch_latest_stories(Site::Contentful::Readme::DeveloperStory, homepage: homepage)
    developer_stories_cache_key = developer_stories.map(&build_cache_key_for_story).join("/")

    {
      # the index view will use this cache_key to perform further caching (via fragment caching)
      cache_key: "#{Digest::SHA256.hexdigest("#{homepage_cache_key}.#{navigation_topics_cache_key}.#{podcasts_cache_key}.#{guides_cache_key}.#{featured_articles_cache_key}.#{developer_stories_cache_key}")}.for_readme_staff:#{@for_readme_staff}/v1",

      homepage_id: homepage.id,
      navigation_topics: navigation_topics.map(&:to_json),

      developer_stories_slugs: developer_stories.map(&:slug),
      podcasts_slugs: podcasts.map(&:slug),
      guides_slugs: guides.map(&:slug),
      featured_articles_slugs: featured_articles.map(&:slug),

      # these cache keys help perform further caching at the view layer
      developer_stories_cache_key: developer_stories_cache_key,
      podcasts_cache_key: podcasts_cache_key,
      guides_cache_key: guides_cache_key,
      featured_articles_cache_key: featured_articles_cache_key,
    }
  end

  private

  def fetch_latest_stories(klass, homepage:)
    klass.get_latest_except(homepage.featured_slugs, include_unpublished: @for_readme_staff, **klass.select_for_index)
  end
end
