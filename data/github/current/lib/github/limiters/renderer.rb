# typed: true
# frozen_string_literal: true

require "api/error_helper"

module GitHub
  module Limiters
    # Public: This middleware tidies up 429 responses.
    class Renderer
      include GitHub::Middleware::Constants

      HTML_PATH = "/public/429#{"-enterprise" if GitHub.enterprise?}.html".freeze
      HTML = [File.read("#{Rails.root}#{HTML_PATH}").freeze].freeze

      JSON_BODY = [File.read("#{Rails.root}/public/429.json").freeze].freeze
      GRAPHQL_JSON_BODY = [File.read("#{Rails.root}/public/graphql_429.json").freeze].freeze

      ALLOW_BODY = "limiter.renderer.allow_body".freeze

      def self.json_for_request_id(request_id, is_graphql: false)
        json_body = is_graphql ? GRAPHQL_JSON_BODY : JSON_BODY
        return json_body unless request_id.present?

        json_with_request_id = is_graphql ? graphql_json_with_request_id : rest_json_with_request_id
        [json_with_request_id.first % request_id]
      end

      def self.rest_json_with_request_id
        @rest_json_with_request_id ||= build_json_with_request_id(JSON_BODY)
      end

      def self.graphql_json_with_request_id
        @graphql_json_with_request_id ||= build_json_with_request_id(GRAPHQL_JSON_BODY)
      end

      def self.build_json_with_request_id(json_body)
        parsed = JSON.parse(json_body.first)
        parsed["message"] += Api::ErrorHelper::RATE_LIMIT_REQUEST_ID_MESSAGE
        [JSON.dump(parsed, pretty: true).freeze].freeze
      end
      private_class_method :build_json_with_request_id

      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = res = @app.call(env)
        return res if status != 429 || !enabled? || allow_body?(env)

        # filter out most headers, we want a minimal 429 (or 403)
        headers.select! { |k, v| allow_header?(k, v) }

        if headers[GH_LIMITED_GROUP] == "api".freeze
          headers[CONTENT_TYPE] = "application/json; charset=utf-8".freeze
          api_semantic_version = Api::MediaType.identify_api_semantic_version(env["REQUEST_PATH"])
          headers["X-GitHub-Media-Type".freeze] = Api::MediaType.semantic_default(api_semantic_version).to_http_header
          body = Renderer.json_for_request_id(Rack::RequestId.get(env), is_graphql: graphql_request?(env))

          [403, headers, body]
        else
          [429, headers.merge!(CONTENT_TYPE => TEXT_HTML), HTML]
        end
      end

      private

      def enabled?
        GitHub.request_limiting_enabled?
      end

      # Internal: Check if the request is a GraphQL request.
      def graphql_request?(env)
        path = env["REQUEST_PATH"] || env["PATH_INFO"]
        ::Api::GraphQL::PATH_REGEX.match?(path)
      end

      # Internal: Allow internal, CORS, and rate limiting headers.
      def allow_header?(name, value)
        /\A(?:Access-Control|GH|X)-/ =~ name || name == "Retry-After".freeze
      end

      # Internal: Allow the returned response body (do not replace it).
      def allow_body?(env)
        !!env[ALLOW_BODY]
      end
    end
  end
end
