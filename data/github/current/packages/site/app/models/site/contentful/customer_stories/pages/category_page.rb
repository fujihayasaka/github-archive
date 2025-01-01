# typed: true
# frozen_string_literal: true

class Site::Contentful::CustomerStories::Pages::CategoryPage < Site::Contentful::Page
  include GitHub::Memoizer

  NUMBER_OF_STORIES_PER_PAGE = 12

  def initialize(category_id:, for_staff: false, **filter_options)
    @category = category_id
    @for_staff = for_staff
    @filter_options = filter_options
  end

  def cache_key
    "site.contentful.customer_stories.pages.category.#{@category}.for_staff:#{@for_staff}"
  end

  def fetch_data_from_contentful
    stories = []
    category_page_data = Site::Contentful::CustomerStories::CategoryPage.content(@category)

    # If category_page_data is nil because the category is invalid, then it can be assumed that no stories will be returned either
    return { page_data: nil, total_stories: 0, stories: [] } if category_page_data.nil?

    if total_stories_count > 0
      stories = Site::Contentful::CustomerStories::CustomerStory.find_stories_by_category(
        category_name,
        limit: NUMBER_OF_STORIES_PER_PAGE,
        fields: Site::Contentful::CustomerStories::CustomerStory.sparse_fields_for_index,
        include_preview: @for_staff,
        **@filter_options
      )
    end

    {
      page_data: category_page_data.to_json,
      stories: stories.map(&:preview_json),
      total_stories: total_stories_count
    }
  end

  def skip_cache?
    @filter_options.present?
  end

  private

  memoize def total_stories_count
    Site::Contentful::CustomerStories::CustomerStory.count(
      fields: {
        categories: category_name,
        preview_story: @for_staff ? nil : "false",
        **@filter_options
      }.compact
    )
  end

  def category_name
    @category.downcase == "all" ? nil : @category.titleize
  end
end
