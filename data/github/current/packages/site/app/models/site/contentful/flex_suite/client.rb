# typed: true
# frozen_string_literal: true

module Site::Contentful::FlexSuite::Client
  extend ActiveSupport::Concern
  include Site::Contentful::Marketing::Client

  class_methods do
    def contentful_client(preview: false, options: {})
      access_token = if preview
        GitHub.contentful_flex_suite_preview_token
      else
        GitHub.contentful_flex_suite_delivery_token
      end

      flex_suite_options = {
        space: GitHub.contentful_flex_suite_space_id,
        access_token: access_token,
        environment: GitHub.contentful_flex_suite_environment,
        max_include_resolution_depth: 7,
        entry_mapping: {
          "page" => Site::Contentful::Marketing::Page,
          "document" => Site::Contentful::Marketing::Document,
        }
      }
      flex_suite_options[:api_url] = GitHub.contentful_preview_api_host if preview

      # Cross-space resource resolution for Customer Stories space
      customer_stories_token = GitHub.contentful_customer_stories_delivery_token
      if customer_stories_token.present?
        resource_resolution = Base64.strict_encode64(JSON.generate({
          "spaces" => {
            GitHub.contentful_customer_stories_space_id => customer_stories_token
          }
        }))
        flex_suite_options[:additional_headers] = {
          "x-contentful-resource-resolution" => resource_resolution
        }
      end

      super(preview: preview, options: flex_suite_options.merge(options))
    end

    def contentful_request(params)
      super
    end

    def contentful_raw_request(params, preview: false)
      super
    end
  end
end
