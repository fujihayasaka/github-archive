# frozen_string_literal: true

require "faraday"

module Dependabot
  module OctokitMiddleware
    class TenancyHeaders < Faraday::Middleware
      attr_reader :tenant

      def initialize(app, options = {})
        super(app)
        @tenant = options.fetch(:tenant) { raise ArgumentError, "Tenant not provided" }
      end

      def call(env)
        return @app.call(env) unless Dependabot.proxima?
        raise ArgumentError, "missing slug" if tenant.slug.blank?

        env[:request_headers]["X-GitHub-Tenant"] = tenant.slug
        @app.call(env)
      end
    end
  end
end
