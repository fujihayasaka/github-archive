# typed: true
# frozen_string_literal: true

require "contentful"

class Site::Contentful::Readme::BaseStory < Site::Contentful::Entry
  extend T::Helpers
  include GitHub::Memoizer
  include Site::Contentful::Readme::Client
  include UrlHelpers
  abstract!

  MAX_GOOD_FIRST_ISSUES = 8

  PUBLICATION_DATE_TIME_ZONE = "Pacific Time (US & Canada)"

  SPARSE_FIELDS_FOR_RSS_FEED = %w(heading metaText publicationDate slug seo)

  sig { abstract.returns(String) }
  def self.category_slug; end

  sig { abstract.returns(String) }
  def self.content_type; end

  sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
  def to_json; end

  def to_param
    slug
  end

  def url
    case content_type.id
    when "guide"
      readme_guide_path(slug)
    when "featured"
      readme_featured_article_path(slug)
    when "developerStory"
      readme_developer_story_path(slug)
    when "podcast"
      readme_podcast_path(slug)
    end
  end

  def self.all(include_unpublished: false, **args)
    params = {
      content_type: self.content_type,
      order: "-fields.publicationDate",
      "fields.publicationDate[lte]": (now_iso_timestamp_in_pst unless include_unpublished),
      **args,
    }.compact

    contentful_request(params)
  end

  def self.find(slug, include_unpublished: false)
    params = {
      content_type: self.content_type,
      "fields.slug": slug.downcase,
      "fields.publicationDate[lte]": (now_iso_timestamp_in_pst unless include_unpublished)
    }.compact

    contentful_request(params)&.first
  end

  def self.select_for_rss_feed
    @@select_for_rss_feed ||= { select: SPARSE_FIELDS_FOR_RSS_FEED.map { |field| "fields.#{field}" }.join(",") }
  end

  def self.select_for_index
    @select_for_index ||= { select: T.must(self.sparse_fields_for_index).map { |field| "fields.#{field}" }.join(",") }
  end

  def self.get_latest_except(slugs, include_unpublished: false, limit: 5, **args)
    params = {
      limit: limit,
      "fields.slug[nin]": slugs.map(&:downcase),
      **args,
    }.compact

    all(include_unpublished: include_unpublished, **params)
  end

  def self.category
    params = {
      content_type: "category",
      "fields.slug": self.category_slug
    }

    contentful_request(params)&.first
  end

  def self.fetch_more_stories_related_to(slug, story_klass:, content_type:, take:, skip:)
    more_stories_params = {
      content_type: content_type,
      order: "-fields.publicationDate",
      limit: take,
      skip: skip,
      **story_klass::select_for_index,
      "fields.slug[nin]": slug.downcase,
      "fields.publicationDate[lte]": now_iso_timestamp_in_pst,
    }.compact

    contentful_request(more_stories_params)
  end

  def self.body(slug)
    stories = contentful_request(
      content_type: self.content_type,
      "fields.slug": slug.downcase,
      select: "fields.body"
    )

    stories&.first&.body
  end

  def featured_article?
    content_type.id == "featured"
  end

  def developer_story?
    content_type.id == "developerStory"
  end

  def guide?
    content_type.id == "guide"
  end

  def podcast?
    content_type.id == "podcast"
  end

  def category_slug
    content_type.id
  end

  def published?
    now_iso_timestamp_in_pst = Time.zone.now.in_time_zone(PUBLICATION_DATE_TIME_ZONE).strftime("%FT%R")
    publication_date.strftime("%FT%R") <= now_iso_timestamp_in_pst
  end

  def nomination_survey
    @survey ||= Site::Readme::NominationSurvey.survey
  end

  def has_approved_sponsors_account?
    # This was dependent on the github_user field. This field only exists on the developer_story.
    # This method can still be called on other readme story types. We always return false for other
    # story types as a precaution, for now.
    false
  end

  # May be overridden by subclasses
  def project_name
  end

  # May be overridden by subclasses
  def github_handle
  end

  def github_user?
    false
  end

  def contributing
  end

  def topic?(topic)
    return false unless respond_to?(:topics)

    topics&.any? { |t| t&.slug == topic }
  end

  def meta_title
    return heading unless seo?

    seo.meta_title || heading
  end

  def meta_description
    return meta_text unless seo?

    seo.meta_description
  end

  def meta_image
    return fields[:meta_image] unless seo?

    seo.meta_image
  end

  def open_graph_title
    return heading unless seo?

    seo.open_graph_title || heading
  end

  def open_graph_description
    return meta_text unless seo?

    seo.open_graph_description || seo.meta_description
  end

  def self.now_iso_timestamp_in_pst
    Time.zone.now.in_time_zone(PUBLICATION_DATE_TIME_ZONE).strftime("%FT%R")
  end

  private

  def name_with_owner?(path)
    return false unless path.present?

    path.split("/").count == 2
  end

  def get_url_path(url)
    return unless url.present?

    T.must(URI::parse(url).path).slice(1..)
  end

  def seo?
    respond_to?(:seo) && seo.present?
  end
end
