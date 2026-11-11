# typed: strict
# frozen_string_literal: true

module FeatureFlag
  module Middleware
    # Adds support for enabling/disabling features for a single request via a
    # ?_features= query parameter. For multiple requests, you can use
    # a `_features` Cookie. The query parameter/cookie value takes a comma-separated
    # list of feature name patterns. If a pattern is preceded by an exclamation
    # point, matching features are disabled for the duration of the request.
    # Otherwise, they are enabled for the duration of the request. Examples:
    #
    #   ?_features=apples  # Enable the apples feature for this request
    #   ?_features=!apples # Disable apples for this request
    #   ?_features=apples,oranges  # Enable apples and oranges
    #   ?_features=apples,!oranges # Enable apples, disable oranges
    #   ?_features=a* # Enable all features with names starting with "a"
    #   ?_features=*  # Enable all features
    #   ?_features=!* # Disable all features
    class Overrider
      extend T::Helpers
      # Public: Initializes an instance of the Overrider middleware.
      #
      # app - The app this middleware is included in.
      # auth_block - An optional block that is passed the request environment
      #              hash. If the block returns falsy, features are not allowed
      #              to be overridden by this request. If the block returns
      #              truthy, features are allowed to be overridden. If no block
      #              is passed, all requests are allowed to override features.
      #
      # Examples
      #
      #   use FeatureFlag::Middleware::Overrider
      #
      #   use FeatureFlag::Middleware::Overrider, lambda { |env| admin_user?(env) }
      #
      sig do
        params(
          app: T.untyped,
          auth_block: T.nilable(T.proc.params(arg0: Rack::Request).returns(T::Boolean))
        ).void
      end
      def initialize(app, auth_block = nil)
        @app = app
        @auth_block = auth_block
      end

      sig { params(env: T::Hash[T.any(String, Symbol), T.untyped]).returns(T::Array[T.untyped]) }
      def call(env)
        ::FeatureFlag.clear_vexi_overrides
        set_overrides(env)

        response = @app.call(env)
        response[2] = Rack::BodyProxy.new(response[2]) do
          ::FeatureFlag.clear_vexi_overrides
        end
        response
      end

      private

      sig { params(env: T::Hash[T.any(String, Symbol), T.untyped]).void }
      def set_overrides(env)
        rack_request = Rack::Request.new(env)
        return if @auth_block && !@auth_block.call(rack_request)

        query_patterns = T.let(rack_request.GET["_features"] || "", String)
        cookie_patterns = T.let(rack_request.cookies["_features"] || "", String)

        return if cookie_patterns.empty? && query_patterns.empty?

        # Remove any nil, whitespace only, or empty patterns
        patterns = (cookie_patterns.split(",") + query_patterns.split(","))
          .compact
          .map(&:strip)
          .reject(&:empty?)

        # Move non exact match patterns to the end so that exact patterns take precedence
        wildcard_patterns, exact_patterns = patterns.partition { |pattern| pattern_has_wildcards?(pattern) }
        patterns = exact_patterns + wildcard_patterns

        # Add patterns to vexi overrides
        patterns.each do |pattern|
          if pattern.start_with?("!")
            pattern = pattern[1..]
            next if pattern.nil? || pattern.empty?
            ::FeatureFlag.add_vexi_override(pattern, enabled: false)
          else
            ::FeatureFlag.add_vexi_override(pattern, enabled: true)
          end
        end
      end

      sig { params(pattern: String).returns(T::Boolean) }
      private def pattern_has_wildcards?(pattern)
        pattern.match?(/[*?\[\]\\{}]/)
      end
    end
  end
end
