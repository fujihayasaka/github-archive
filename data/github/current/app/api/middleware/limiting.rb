# typed: true
# frozen_string_literal: true

# Public: Applies one or more GitHub::Limiters to API requests.
module Api
  module Middleware
    class Limiting < GitHub::Limiters::Middleware
      include GitHub::ServiceMapping

      # Internal: Requests with paths matching these patterns are ignored from
      # request limiting.
      IGNORED_PATHS = [
        %r{\A/status\z}i,
        %r{\A/_private}i,
        %r{\A/lfs}i,
      ].freeze

      RATE_LIMIT_PATH = %r{\A/rate_limit\z}i.freeze

      # Internal: Requests with these Internal API versions are ignored for
      # request limiting.
      IGNORED_VERSIONS = [
        # Raw API
        "hyperion",
        # Avatars API
        "drstrange",
        # Ping for Internal API
        "smasher",
      ]

      class Disabled < Limiting
        # Disabled by default, but with a query string override for testing
        def enabled?(env)
          super(env) && (query = env[QUERY_STRING]) && query.include?("enable-limiters")
        end
      end

      def initialize(app, *limiters)
        super(*T.unsafe([app, "api", *limiters]))
      end

      def call(env)
        push_service_mapping_context(env: env) do
          super
        end
      end

      protected

      def enabled?(env)
        # Don't track rate limits for varnished requests. This is handled
        # at the Varnish layer already.
        return false if GitHub.varnish_enabled? && env["HTTP_X_GITHUB_DYNAMIC_CACHE"] == "api"
        GitHub.request_limiting_enabled?
      end

      def ignored?(env)
        super || ignored_path?(env) || ignored_version?(env)
      end

      def ignored_path?(env)
        return true if Regexp.union(IGNORED_PATHS).match(env[PATH_INFO])

        false
      end

      def ignored_version?(env)
        accept = env[HTTP_ACCEPT]
        path_info = env[PATH_INFO]

        versions = Api::AcceptedMediaTypes.new(accept, path_info).semantic_versions

        !(IGNORED_VERSIONS & versions).empty?
      end

      def append_to_hydro_payload(env, hydro_payload)
        hydro_payload["request_category"] = "api"
        route = GitHub::TaggingHelper.api_route(env)

        if api_route = GitHub::TaggingHelper.api_action(route)
          hydro_payload["api_route"] = api_route
        end
      end
    end
  end
end
