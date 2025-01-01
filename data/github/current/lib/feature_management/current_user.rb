# typed: true
# frozen_string_literal: true

module FeatureManagement
  # Faraday middleware that inserts a placeholder for the current user name used by the feature flag hub for auditing to downstream services.
  class CurrentUser < ::Faraday::Middleware
    GITHUB_USER_HEADER = "X-GitHub-User".freeze
    FORWARDER_USER = "MySQLAdapter"

    def call(env)
      env.request_headers[GITHUB_USER_HEADER] = FORWARDER_USER
      @app.call(env)
    end
  end

  # Faraday middleware that inserts a placeholder for the current user name used by the feature flag hub for auditing to downstream services.
  class VexiUser < ::Faraday::Middleware
    GITHUB_USER_HEADER = "X-GitHub-User".freeze
    VEXI_USER = "Vexi"

    def call(env)
      env.request_headers[GITHUB_USER_HEADER] = VEXI_USER
      @app.call(env)
    end
  end
end
