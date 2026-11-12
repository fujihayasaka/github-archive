# frozen_string_literal: true

module Dependabot
  module OctokitMiddleware
    # Adds an authorization header using an access token provided by options[:token].
    # On an unauthorized error response, will retry up to options[:max_retries] times
    # using a regenerated token provided by options[:regenerate_token_callback].
    class AccessTokenAuthentication < Faraday::Middleware
      AUTHORIZATION = "Authorization"

      def initialize(app, options = {})
        @app = app
        @token = options[:token]
        @tenant = options[:tenant]
        @regenerate_token_callback = options[:regenerate_token_callback]
        @max_retries = options[:max_retries]
      end

      def call(env)
        env.request_headers[AUTHORIZATION] = "token #{@token}"
        env.request_headers["X-GitHub-Tenant"] = @tenant.slug if @tenant.slug.present?
        @app.call(env)
      rescue Octokit::Unauthorized => e
        attempt ||= 0
        attempt += 1

        raise unless e.message.include?("Bad credentials")
        raise unless attempt <= @max_retries
        raise unless (token = @regenerate_token_callback&.call)

        @token = token
        retry
      end
    end
  end
end
