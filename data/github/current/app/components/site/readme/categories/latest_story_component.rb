# typed: strict
# frozen_string_literal: true

class Site::Readme::Categories::LatestStoryComponent < ApplicationComponent
  extend T::Sig

  sig { params(story_klass: T.class_of(Site::Contentful::Readme::BaseStory), for_readme_staff: T::Boolean).returns(String) }
  def self.cache_key_for_story_klass(story_klass, for_readme_staff:)
    "site.contentful.readme.categories.#{story_klass.category_slug}.latest_story.for_readme_staff:#{for_readme_staff}"
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

  sig { returns(T::Hash[Symbol, T.untyped]) }
  memoize def story
    cache_key = self.class.cache_key_for_story_klass(@story_klass, for_readme_staff: @for_readme_staff)

    story_data = GitHub.cache.fetch(cache_key, { ttl: 8.hours, stats_key: cache_key, force: @force_cache_miss }) do
      fresh_stories = @story_klass.all(
        include_unpublished: @for_readme_staff,
        limit: 1,
        **@story_klass::select_for_index,
      )

      fresh_latest_story = fresh_stories.first

      JSON.generate(fresh_latest_story.to_json)
    end

    JSON.parse(story_data, symbolize_names: true)
  end

  sig { returns(String) }
  memoize def mask_number
    %w[1 2 3].sample
  end

  sig { returns(T::Boolean) }
  def apply_mask?
    story[:developer_story?]
  end
end
