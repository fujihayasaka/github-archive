# typed: true
# frozen_string_literal: true

require "contentful"

class Site::Contentful::Marketing::Document < Contentful::Entry
  include Site::Contentful::Marketing::Client

  def self.find(path)
    params = {
      content_type: "document",
      "fields.path": path,
    }.compact

    contentful_request(params)&.first
  end
end
