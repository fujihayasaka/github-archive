# typed: true
# frozen_string_literal: true

require "contentful"

module Site::Contentful::Marketing::Client
  extend ActiveSupport::Concern

  class_methods do
    include Kernel

    def contentful_client(options = {})
      if Rails.env.development?
        require "dotenv/load"
      end

      base_contentful_client_options = {
        space: GitHub.contentful_marketing_space_id,
        access_token: GitHub.contentful_marketing_delivery_token,
        environment: GitHub.contentful_marketing_environment,
        max_include_resolution_depth: 7,
        entry_mapping: {
          "page" => Site::Contentful::Marketing::Page,
          "document" => Site::Contentful::Marketing::Document,
          "entry_startup_partner" => Site::Contentful::Marketing::Startups::StartupPartner,
          "entry_press_article" => Site::Contentful::Marketing::Press::Article,
        }
      }

      Site::Contentful::Client.new(base_contentful_client_options.merge(options))
    end

    def contentful_request(params)
      contentful_client.entries(params)
    rescue Contentful::RateLimitExceeded => err
      # A Contentful::RateLimitExceeded might happen, e.g. when we query a wrong content_type.
      # This could happen due to an accidental change on Contentful.
      # In production this returns nil, which will result in a 404.

      GitHub.dogstats.increment(
        "site.contentful.failures",
        tags: ["method:#{__method__}", "error:#{err.class}"]
      )

      raise if Rails.env.development?
    rescue Contentful::BadRequest => err
      # A Contentful::BadRequest might happen, e.g. when we query a wrong content_type.
      # This could happen due to an accidental change on Contentful.
      # In production this returns nil, which will result in a 404.

      GitHub.dogstats.increment(
        "site.contentful.failures",
        tags: ["method:#{__method__}",  "error:#{err.class}"]
      )

      raise if Rails.env.development?
    end

    def contentful_raw_request(params)
      contentful_client(raw_mode: true).entries(params).load_json
    rescue Contentful::RateLimitExceeded => err
      GitHub.dogstats.increment(
        "site.contentful.failures",
        tags: ["method:#{__method__}",  "error:#{err.class}"]
      )

      raise if Rails.env.development?
    rescue Contentful::BadRequest => err
      GitHub.dogstats.increment(
        "site.contentful.failures",
        tags: ["method:#{__method__}",  "error:#{err.class}"]
      )

      raise if Rails.env.development?
    end
  end
end
