# typed: true
# frozen_string_literal: true

require "contentful"

class Site::Contentful::Marketing::Events::Event < Site::Contentful::Entry
  include Site::Contentful::Marketing::Client, Site::Contentful::Query

  def self.content_type
    "entry_event"
  end

  def self.find(slug)
    query(fields: { slug: slug.downcase }).first
  end

  def self.active
    query(fields: { endDate: { gte: Date.today }, sponsored: false }, order: "fields.startDate")
  end

  def self.persistent
    query(fields: { alwaysShow: true, sponsored: false })
  end

  def self.sponsored
    query(fields: { endDate: { gte: Date.today }, sponsored: true })
  end

  def to_json
    {
      name: name,
      slug: slug&.downcase,
      always_show: always_show,
      external_url: external_url,
      start_date: start_date&.iso8601,
      end_date: end_date&.iso8601,
      alternative_date_text: alternative_date_text,
      image: {
        url: image&.url
      },
      location_full_address: location_full_address,
      location_short_name: location_short_name,
      short_description: short_description,
      sponsored: sponsored,
      topics: topics,
      content: content,
    }
  end
end
