# typed: true
# frozen_string_literal: true

require "contentful"

class Site::Contentful::Readme::Topic < Site::Contentful::Entry
  include Site::Contentful::Readme::Client

  def self.content_type
    "topic"
  end

  ALLOWED_STORY_CONTENT_TYPE_KLASSES = [
    Site::Contentful::Readme::FeaturedArticle,
    Site::Contentful::Readme::DeveloperStory,
    Site::Contentful::Readme::Guide,
    Site::Contentful::Readme::Podcast
  ].freeze

  NAVIGATION_TOPICS_CACHE_KEY = "site.contentful.readme.navigation_topics"

  def self.all(include_unpublished: false)
    params = {
      content_type: content_type,
      "order": "fields.name",
      "fields.public": (true unless include_unpublished)
    }.compact

    contentful_request(params)
  end

  def self.find(slug, include_unpublished: false)
    params = {
      content_type: content_type,
      "fields.slug": slug.downcase,
      "fields.public": (true unless include_unpublished)
    }.compact

    contentful_request(params)&.first
  end

  def self.navigation_topics
    contentful_request(content_type: "navigation")&.first&.topics
  end

  def self.find_stories_for(id, take: nil)
    slicing_options = take.present? ? { limit: take } : {}

    contentful_responses = ALLOWED_STORY_CONTENT_TYPE_KLASSES.map do |klass|
      contentful_request(
        content_type: klass.content_type,
        order: "-fields.publicationDate",
        "links_to_entry": id,
        "fields.publicationDate[lte]": klass::now_iso_timestamp_in_pst,
        **klass::select_for_index,
        **slicing_options
      )
    end

    all_entries = contentful_responses.flatten.sort_by(&:publication_date).reverse

    return all_entries if take.nil?

    all_entries.take(take)
  end

  def to_param
    slug
  end

  def to_json
    {
      id: id,
      meta_text: meta_text,
      name: name,
      slug: slug,
    }
  end
end
