# typed: true
# frozen_string_literal: true

module GitHub
  module Stats
    module Api
      extend self

      # Public: Throws Api stats at statsd.
      #
      # options - The Hash containing stats to be recorded (default: {}).
      #           :catalog_service             - Catalog service for the API endpoint (e.g. issues)
      #           :version                     - Version of the API (e.g., "beta", "v3", "superman-preview").
      #           :auth                        - Type of authentication [anon, basic, token, oauth, apps].
      #           :route                       - The identifier/route of this API call, (e.g. "/gists/:id/star')
      #           :controller                  - The controller of this API call, (e.g. "api_root')
      #           :method                      - The HTTP method (e.g., "GET", "POST", etc)
      #           :elapsed                     - The elapsed response time in seconds
      #           :status                      - HTTP Response code
      #           :requested_api_version       - The API version requested by the client
      #           :selected_api_version        - The API version selected by the API
      #           :selected_api_version_reason - The reason for picking the selected API version
      #
      # Returns nothing.
      def record(options)
        tag_names = [
          GitHub::TaggingHelper::CATALOG_SERVICE_TAG,
          GitHub::TaggingHelper::CONTROLLER_TAG,
          GitHub::TaggingHelper::ROUTE_TAG,
          GitHub::TaggingHelper::METHOD_TAG,
          GitHub::TaggingHelper::AUTH_TAG,
          GitHub::TaggingHelper::STATUS_TAG,
          GitHub::TaggingHelper::STATUS_RANGE_TAG,
          GitHub::TaggingHelper::REQUESTED_API_VERSION_TAG,
          GitHub::TaggingHelper::SELECTED_API_VERSION_TAG,
          GitHub::TaggingHelper::SELECTED_API_VERSION_REASON_TAG,
          GitHub::TaggingHelper::VERSION_TAG,
        ]

        tags = []

        tag_names.each do |tag_name|
          if options[tag_name].is_a?(Enumerable)
            options[tag_name].each { |tag_value| GitHub::TaggingHelper.add_tag(tags, tag_name, tag_value || GitHub::TaggingHelper::UNKNOWN) }
          else
            GitHub::TaggingHelper.add_tag(tags, tag_name, options[tag_name] || GitHub::TaggingHelper::UNKNOWN)
          end
        end

        GitHub.dogstats.distribution("request.api.dist.time", options[:elapsed], tags: tags)
      end
    end
  end
end
