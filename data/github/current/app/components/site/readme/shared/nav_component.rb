# typed: true
# frozen_string_literal: true

class Site::Readme::Shared::NavComponent < ApplicationComponent
  include SvgHelper
  include UrlHelper

  CACHE_KEY = "site.contentful.readme.navigation_topics"

  # This component can either get a list of topics or request the list by itself.
  #
  # If it receives a list of topics, it will use it. Otherwise, it will make a
  # request to Contentful or use the cached list. It is possible to force
  # a cache miss by passing `force_cache_miss: true`.
  #
  # As we continue adopting Page models, we should consider getting rid of
  # the ability to request a list of topics directly from this component and
  # make it work with `topics:` instead.
  def initialize(force_cache_miss: false, topics: nil)
    @force_cache_miss = force_cache_miss
    @topics = topics
  end

  memoize def topics
    return @topics unless @topics.nil?
    navigation_topics_data = GitHub.cache.fetch(CACHE_KEY, { ttl: 8.hours, stats_key: CACHE_KEY, force: @force_cache_miss }) do
      fresh_navigation_topics = Site::Contentful::Readme::Topic.navigation_topics

      JSON.generate(fresh_navigation_topics.map(&:to_json))
    end

    JSON.parse(navigation_topics_data, symbolize_names: true)
  end

  def categories
    [
      { link: readme_featured_articles_path, name: "Featured Articles" },
      { link: readme_developer_stories_path, name: "Developer Stories" },
      { link: readme_guides_path, name: "Guides" },
      { link: readme_podcasts_path, name: "The ReadMe Podcast" }
    ]
  end
end
