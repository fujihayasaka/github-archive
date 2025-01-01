# typed: true
# frozen_string_literal: true

require "contentful"

class Site::Contentful::CustomerStories::Testimonial < Site::Contentful::Entry
  include Site::Contentful::CustomerStories::Client, Site::Contentful::Query

  def self.content_type
    "testimonial"
  end

  def self.find(name)
    query(fields: { name: name }, limit: 1).first
  end

  def to_json
    {
      quote: quote,
      name: name,
      position: position,
      company: company,
      profile: profile&.to_json,
    }
  end
end
