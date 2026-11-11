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

  class VexiManagementUser < ::Faraday::Middleware
    GITHUB_USER_HEADER = "X-GitHub-User".freeze
    VEXI_MANAGEMENT_USER = "VexiManagement"

    def call(env)
      if FeatureFlag.vexi.enabled?(:vexi_management_caller_tracking, default: false)
        current_management_user = Thread.current.fetch(FeatureFlag::Client::VexiManagementWithCallTracking::VEXI_MANAGEMENT_CALLER_KEY) { VEXI_MANAGEMENT_USER }
        env.request_headers[GITHUB_USER_HEADER] = current_management_user
      else
        env.request_headers[GITHUB_USER_HEADER] = VEXI_MANAGEMENT_USER
      end
      @app.call(env)
    end
  end

  class FeatureFlagDataUser < ::Faraday::Middleware
    GITHUB_USER_HEADER = "X-GitHub-User".freeze

    def call(env)
      env.request_headers[GITHUB_USER_HEADER] = GitHub.context[:actor] || "unknown"
      @app.call(env)
    end
  end
end
