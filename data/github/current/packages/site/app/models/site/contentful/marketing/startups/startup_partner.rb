# typed: true
# frozen_string_literal: true

require "contentful"

class Site::Contentful::Marketing::Startups::StartupPartner < Site::Contentful::Entry
  include Site::Contentful::Marketing::Client

  CONTENTFUL_REQUEST_LIMIT = 1000

  def self.content_type
    "entry_startup_partner"
  end

  def self.all
    params = {
      content_type: content_type,
      "order": "fields.name",
      limit: CONTENTFUL_REQUEST_LIMIT,
    }.compact

    contentful_request(params)
  end

  def to_json
    {
      name: name,
      type: type,
      country: country,
      website: website
    }
  end
end
