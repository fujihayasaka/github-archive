# typed: true
# frozen_string_literal: true

module GitHub
  module FaradayMiddleware
    # Faraday middleware that inserts the two headers required to pass the
    # GitHub request ID on to downstream services.
    class RequestAnalytics < ::Faraday::Middleware
      GITHUB_ACTOR_ID_HEADER = "X-GitHub-Actor-Id".freeze
      GITHUB_INSTALLATION_ID_HEADER = "X-GitHub-Installation-Id".freeze
      GITHUB_SSII_REPO_ID_HEADER = "X-GitHub-Site-Scoped-Integration-Installation-Repo-Id".freeze
      GITHUB_SSII_TARGET_ID_HEADER = "X-GitHub-Site-Scoped-Integration-Installation-Target-Id".freeze

      def call(env)
        if GitHub.context[:actor_id]
          env.request_headers[GITHUB_ACTOR_ID_HEADER] = GitHub.context[:actor_id]
        end

        if GitHub.context[:installation_id]
          env.request_headers[GITHUB_INSTALLATION_ID_HEADER] = GitHub.context[:installation_id]
        end

        if GitHub.context[:site_scoped_integration_installation_target_id]
          env.request_headers[GITHUB_SSII_TARGET_ID_HEADER] = GitHub.context[:site_scoped_integration_installation_target_id]
        end

        if GitHub.context[:site_scoped_integration_installation_repo_id]
          env.request_headers[GITHUB_SSII_REPO_ID_HEADER] = GitHub.context[:site_scoped_integration_installation_repo_id]
        end

        @app.call(env)
      end
    end
  end
end
