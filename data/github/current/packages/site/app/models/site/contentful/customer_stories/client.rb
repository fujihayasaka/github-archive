# typed: true
# frozen_string_literal: true

require "contentful"

module Site::Contentful::CustomerStories::Client
  extend ActiveSupport::Concern

  class_methods do
    include Kernel

    def contentful_client
      if Rails.env.development?
        require "dotenv/load"
      end

      Site::Contentful::Client.new(
        space: GitHub.contentful_customer_stories_space_id,
        access_token: GitHub.contentful_customer_stories_delivery_token,
        environment: GitHub.contentful_customer_stories_environment,
        max_include_resolution_depth: 3,
        entry_mapping: {
          "pageIndexPage" => Site::Contentful::CustomerStories::Homepage,
          "story" => Site::Contentful::CustomerStories::CustomerStory,
          "testimonial" => Site::Contentful::CustomerStories::Testimonial,
          "categoryPage" => Site::Contentful::CustomerStories::CategoryPage,
        },
        resource_mapping: {
          "Asset" => Site::Contentful::Asset,
        }
      )
    end

    def contentful_request(params)
      contentful_client.entries(params)
    rescue Contentful::BadRequest
      # A Contentful::BadRequest might happen, e.g. when we query a wrong content_type.
      # This could happen due to an accidental change on Contentful.
      # In production this returns nil, which will result in a 404.
      raise if Rails.env.development?
    end
  end
end
