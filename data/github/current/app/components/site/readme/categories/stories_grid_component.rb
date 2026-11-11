# typed: strict
# frozen_string_literal: true

class Site::Readme::Categories::StoriesGridComponent < ApplicationComponent

  sig { params(story_klass: T.class_of(Site::Contentful::Readme::BaseStory), for_readme_staff: T::Boolean).returns(String) }
  def self.cache_key_for_story_klass(story_klass, for_readme_staff:)
    "site.contentful.readme.categories.#{story_klass.category_slug}.grid.for_readme_staff:#{for_readme_staff}"
  end

  sig do
    params(
      for_readme_staff: T::Boolean,
      story_klass: T.class_of(Site::Contentful::Readme::BaseStory),
      force_cache_miss: T::Boolean
    ).void
  end
  def initialize(for_readme_staff:, story_klass:, force_cache_miss: false)
    @for_readme_staff = for_readme_staff
    @story_klass = story_klass
    @force_cache_miss = force_cache_miss
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  memoize def stories
    cache_key = self.class.cache_key_for_story_klass(@story_klass, for_readme_staff: @for_readme_staff)

    stories_data = GitHub.cache.fetch(cache_key, { ttl: 8.hours, stats_key: cache_key, force: @force_cache_miss }) do
      fresh_stories = @story_klass.all(include_unpublished: @for_readme_staff, **@story_klass::select_for_index)

      JSON.generate(fresh_stories.drop(1).map(&:to_json))
    end


    JSON.parse(stories_data, symbolize_names: true)
  end
end
