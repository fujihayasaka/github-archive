# typed: true
# frozen_string_literal: true

require "contentful"

module Site::Contentful::Readme::Client
  extend ActiveSupport::Concern

  MAX_INCLUDE_RESOLUTION_DEPTH = 3

  class_methods do
    include Kernel

    def contentful_client
      if Rails.env.development?
        require "dotenv/load"
      end

      Site::Contentful::Client.new(
        space: GitHub.contentful_readme_space_id,
        access_token: GitHub.contentful_readme_delivery_token,
        environment: GitHub.contentful_readme_environment,
        max_include_resolution_depth: MAX_INCLUDE_RESOLUTION_DEPTH,
        entry_mapping: {
          "guide" => Site::Contentful::Readme::Guide,
          "featured" => Site::Contentful::Readme::FeaturedArticle,
          "developerStory" => Site::Contentful::Readme::DeveloperStory,
          "podcast" => Site::Contentful::Readme::Podcast,
          "topic" => Site::Contentful::Readme::Topic,
          "category" => Site::Contentful::Readme::Category,
          "homepage" => Site::Contentful::Readme::Homepage
        },
        resource_mapping: {
          "Asset" => Site::Contentful::Asset,
        }
      )
    end

    def contentful_request(params)
      to_include = params.fetch(:include, MAX_INCLUDE_RESOLUTION_DEPTH)
      contentful_client.entries(params.merge(include: to_include))
    rescue Contentful::BadRequest
      # A Contentful::BadRequest might happen, e.g. when we query a wrong content_type.
      # This could happen due to an accidental change on Contentful.
      # In production this returns nil, which will result in a 404.
      raise if Rails.env.development?
    end
  end
end
