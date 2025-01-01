# typed: true
# frozen_string_literal: true

class Site::Contentful::CustomerStories::Pages::IndexPage < Site::Contentful::Page
  include GitHub::Memoizer

  NUMBER_OF_STORIES_TO_DISPLAY = 6
  # This gives the illusion of randomization by shuffling through filters that have at least 6 stories
  # A random int betweeen 1 and total (minus NUMBER_OF_STORIES_TO_DISPLAY) could have been used but requires an additional request
  RANDOMIZED_ENTERPRISE_FILTERS = [
    { industry_filters: "Financial services" },
    { industry_filters: "Manufacturing" },
    { industry_filters: "Media & Entertainment" },
    { industry_filters: "Retail & ecommerce" },
    { industry_filters: "Software, Hardware & Technology" },
    { product_filters: "GitHub Advanced Security" },
    { regions: "Americas" },
    { regions: "Europe" },
    { regions: "Middle East & Africa" },
  ].freeze
  ORDER_OPTIONS = ["sys.id", "-sys.id", "fields.title", "-fields.title"].freeze

  def initialize(for_staff: false, cache_version: :v3)
    @for_staff = for_staff
    @cache_version = cache_version
  end

  def cache_key
    case @cache_version
    when :v1 then "site.contentful.customer_stories.pages.index.for_staff:#{@for_staff}"
    when :v2 then "site.contentful.customer_stories.pages.index.v2.for_staff:#{@for_staff}"
    when :v3 then "site.swp.customer_stories.index.staff:#{@for_staff}"
    else
      raise "Invalid cache version: #{@cache_version}"
    end
  end

  def fetch_data_from_contentful
    homepage = Site::Contentful::CustomerStories::Homepage.content

    enterprise_stories = Site::Contentful::CustomerStories::CustomerStory.find_stories_by_category(
      Site::Contentful::CustomerStories::Categories::ENTERPRISE,
      limit: NUMBER_OF_STORIES_TO_DISPLAY,
      include_preview: @for_staff,
      order: random_order,
      **random_enterprise_filter
    )

    team_stories = Site::Contentful::CustomerStories::CustomerStory.find_stories_by_category(
      Site::Contentful::CustomerStories::Categories::TEAM,
      limit: NUMBER_OF_STORIES_TO_DISPLAY,
      include_preview: @for_staff,
      order: random_order,
    )

    data = {
      homepage: homepage.to_json,
      enterprise_stories: enterprise_stories.map(&:preview_json),
      team_stories: team_stories.map(&:preview_json),
    }
    data.merge!(updated_at: Time.now.utc) if @cache_version == :v2
    data
  end

  def revalidate_if_stale
    revalidate_async if stale?
  end

  def revalidate_async
    RevalidatePageJob.perform_later(self.class, for_staff: @for_staff, cache_version: @cache_version)
  end

  sig { returns(T::Boolean) }
  def stale?
    return true if updated_at.nil?
    (T.must(updated_at) + revalidate_in) < Time.now.utc
  end

  def revalidate_in
    1.hour
  end

  sig { returns(T.nilable(Time)) }
  memoize def updated_at
    updated = view_data[:updated_at]

    case updated
    when Time then updated
    when String then Time.parse(updated)
    else
      nil
    end
  end

  private

  def random_enterprise_filter
    RANDOMIZED_ENTERPRISE_FILTERS.sample
  end

  def random_order
    ORDER_OPTIONS.sample
  end
end
