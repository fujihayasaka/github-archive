# typed: true
# frozen_string_literal: true

class Site::Contentful::Readme::Pages::Topics::IndexPage < Site::Contentful::Page
  include Site::Contentful::Readme::Pages::Fetchers::NavigationTopicsFetcher

  def initialize(for_readme_staff: false)
    @for_readme_staff = for_readme_staff
  end

  sig { override.returns(String) }
  def cache_key
    "site.swp.readme.topics.index.staff:#{@for_readme_staff}"
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    navigation_topics = fetch_navigation_topics.map(&:to_json)

    topics_with_stories = Site::Contentful::Readme::Topic.all(include_unpublished: @for_readme_staff).map do |topic|
      stories = Site::Contentful::Readme::Topic.find_stories_for(topic.id, take: 2)

      [topic.to_json, stories.map(&:to_json)]
    end

    { navigation_topics: navigation_topics, topics_with_stories: topics_with_stories }
  end
end
