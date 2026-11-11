# typed: true
# frozen_string_literal: true

require "contentful"

class Site::Contentful::Readme::Homepage < Site::Contentful::Entry
  include Site::Contentful::Readme::Client

  def self.content_type
    "homepage"
  end

  PUBLICATION_DATE_TIME_ZONE = "Pacific Time (US & Canada)"

  def self.latest(include_unpublished: false)
    params = {
      content_type: content_type,
      order: "-fields.publicationDate",
      limit: 1,
      include: 3,
      "fields.publicationDate[lte]": (now_iso_timestamp_in_pst unless include_unpublished)
    }.compact

    contentful_request(params)&.first
  end

  def self.fetch_by_id(id)
    params = {
      "sys.id": id,

      content_type: content_type,
      include: 3,
      limit: 1,
    }

    contentful_request(params)&.first
  end

  def featured_slugs
    return [] if featured_content.nil?
    @featured_slugs ||= T.must(featured_content).map(&:slug)
  end

  def published?
    now_iso_timestamp_in_pst = Time.zone.now.in_time_zone(PUBLICATION_DATE_TIME_ZONE).strftime("%FT%R")
    publication_date&.strftime("%FT%R") < now_iso_timestamp_in_pst
  end

  def self.now_iso_timestamp_in_pst
    Time.zone.now.in_time_zone(PUBLICATION_DATE_TIME_ZONE).strftime("%FT%R")
  end
  private_class_method :now_iso_timestamp_in_pst
end
