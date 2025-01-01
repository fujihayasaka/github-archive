# typed: true
# frozen_string_literal: true

module Flipper
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
      # Public: Initializes an instance of the Overrider middleware.
      #
      # app - The app this middleware is included in.
      # flipper_or_block - The Flipper::DSL instance or a block that yields a
      #                    Flipper::DSL instance to use for all operations. The
      #                    Flipper::DSL's adapter must be using the
      #                    Flipper::Adapters::Override decorator.
      # auth_block - An optional block that is passed the request environment
      #              hash. If the block returns falsy, features are not allowed
      #              to be overridden by this request. If the block returns
      #              truthy, features are allwoed to be overridden. If no block
      #              is passed, all requests are allowed to override features.
      #
      # Examples
      #
      #   flipper = Flipper.new(...)
      #
      #   # using with a normal flipper instance
      #   use Flipper::Middleware::Overrider, flipper
      #
      #   # using with a block that yields a flipper instance
      #   use Flipper::Middleware::Overrider, lambda { Flipper.new(...) }
      #
      #   # using an auth block
      #   use Flipper::Middleware::Overrider, flipper, lambda { |env| admin_user?(env) }
      #
      def initialize(app, flipper_or_block, auth_block = nil)
        @app = app

        if flipper_or_block.respond_to?(:call)
          @flipper_block = flipper_or_block
        else
          @flipper = flipper_or_block
        end

        @auth_block = auth_block
      end

      def flipper
        @flipper ||= @flipper_block.call
      end

      def call(env)
        set_overrides(env)

        response = @app.call(env)
        response[2] = Rack::BodyProxy.new(response[2]) do
          flipper.adapter.reset_overrides
        end
        response
      end

      private

      def set_overrides(env)
        rack_request = Rack::Request.new(env)
        return if @auth_block && !@auth_block.call(rack_request)

        query_patterns = rack_request.GET["_features"] || ""
        cookie_patterns = rack_request.cookies["_features"] || ""

        return if query_patterns.empty? && cookie_patterns.empty?

        patterns = query_patterns.split(",") | cookie_patterns.split(",")

        patterns.each do |pattern|
          if pattern.start_with?("!")
            flipper.adapter.override_features(pattern[1..-1], enabled: false)
          else
            flipper.adapter.override_features(pattern, enabled: true)
          end
        end
      end
    end
  end
end
