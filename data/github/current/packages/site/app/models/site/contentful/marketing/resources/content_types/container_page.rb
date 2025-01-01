# typed: true
# frozen_string_literal: true

require "contentful"

class Site::Contentful::Marketing::Resources::ContentTypes::ContainerPage < Contentful::Entry
  include Site::Contentful::Marketing::Client

  def self.get_raw_json_for(slug)
    params = {
      content_type: "containerPage",
      "fields.path": slug,
      include: 10,
    }

    contentful_raw_request(params)
  end

  def self.get_raw_json_full_search_path_for(slug)
    params = {
      content_type: "containerPage",
      "fields.path[match]": slug,
      include: 10,
      limit: 1000
    }

    contentful_raw_request(params)
  end
end
