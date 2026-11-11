# typed: true
# frozen_string_literal: true

require "contentful"

class Site::Contentful::Marketing::Page < Contentful::Entry
  include Site::Contentful::Marketing::Client

  # In order to reduce round trips to Contentful, we want to include associated entries within one request.
  #
  # An example would be:
  #   Page -> Content -> Sections -> Component -> Person -> Image
  #
  # https://www.contentful.com/developers/docs/references/content-delivery-api/#/reference/links
  NUMBER_OF_LINKED_ENTRIES = 8

  def self.find(slug)
    params = {
      content_type: "page",
      "fields.slug": slug,
      include: NUMBER_OF_LINKED_ENTRIES
    }.compact

    contentful_request(params)&.first
  end
end
