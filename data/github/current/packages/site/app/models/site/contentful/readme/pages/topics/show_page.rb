# typed: true
# frozen_string_literal: true

class Site::Contentful::Readme::Pages::Topics::ShowPage < Site::Contentful::Page
  include Site::Contentful::Readme::Pages::Fetchers::NavigationTopicsFetcher

  def initialize(topic_slug:, for_readme_staff: false)
    @topic_slug = topic_slug
    @for_readme_staff = for_readme_staff
  end

  def cache_key
    "site.swp.readme.topics.#{@topic_slug}.staff:#{@for_readme_staff}"
  end

  def fetch_data_from_contentful
    topic = Site::Contentful::Readme::Topic.find(@topic_slug, include_unpublished: @for_readme_staff)

    return { navigation_topics: [], stories: [], topic: nil } unless topic.present?

    stories_updated_at_digest = Digest::SHA256.hexdigest(
      Site::Contentful::Readme::Topic.find_stories_for(topic.id).map(&:updated_at).map(&:iso8601).join(".")
    )

    # The number of stories is too large to be cached in a single key. So, instead of using the Page to cache
    # all the stories (that wouldn't fit in a single key on GitHub.kv), we cache a string representing the
    # updated_at of each story. This way, we can invalidate the cache when a story is updated.
    #
    # Then, this string is used to cache the stories themselves using fragment caching in the view.
    {
      navigation_topics: fetch_navigation_topics.map(&:to_json),
      stories_cache_key: "#{stories_updated_at_digest}.for_readme_staff:#{@for_readme_staff}/v1",
      topic: topic.to_json,
    }
  end
end
