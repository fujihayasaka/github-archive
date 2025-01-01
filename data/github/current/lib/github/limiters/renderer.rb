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
      json_parsed = JSON.parse(JSON_BODY.first)
      json_parsed["message"] += Api::ErrorHelper::RATE_LIMIT_REQUEST_ID_MESSAGE
      JSON_WITH_REQUEST_ID = [JSON.dump(json_parsed, pretty: true).freeze].freeze

      ALLOW_BODY = "limiter.renderer.allow_body".freeze

      def self.json_for_request_id(request_id)
        return JSON_BODY unless request_id.present?

        [JSON_WITH_REQUEST_ID.first % request_id]
      end

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
          body = Renderer.json_for_request_id(Rack::RequestId.get(env))

          [403, headers, body]
        else
          [429, headers.merge!(CONTENT_TYPE => TEXT_HTML), HTML]
        end
      end

      private

      def enabled?
        GitHub.request_limiting_enabled?
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
