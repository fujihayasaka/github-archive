# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module AzureExperimentsV2
      def azure_experiments_v2_tas_scheme
        if GitHub::AppEnvironment.development? || GitHub.service_mesh_enabled?
          "http"
        else
          "https"
        end
      end

      def azure_experiments_v2_tas_host
        url = GitHub.environment.fetch("AZURE_EXPERIMENTS_V2_TAS_URL", nil)
        return url if url

        if Rails.env.test?
          return "fake-azure-experiments-v2-tas-url.github.com"
        end

        if GitHub::AppEnvironment.development?
          return "localhost:18080"
        end

        if (Rails.env.production? || GitHub.employee_unicorn? || GitHub.review_lab? || GitHub.staff_host?) && !GitHub.enterprise?
          if GitHub.service_mesh_enabled?
            return "rest.exp-tas-production.svc.cluster.local:8080"
          else
            return "exp-tas-rest-production.service.iad.github.net"
          end
        end

        nil
      end

      def azure_experiments_v2_tas_url
        host = azure_experiments_v2_tas_host
        return nil unless host

        # If the host came from an ENV override, it may already include a scheme.
        return host if host.start_with?("http://", "https://")

        "#{azure_experiments_v2_tas_scheme}://#{host}"
      end

      # Circuit breaker: minimum requests before tripping. Zero in test so the
      # breaker can be exercised with a single call.
      def azure_experiments_v2_resilient_request_volume_threshold
        GitHub::AppEnvironment.test? ? 0 : 20
      end

      # Circuit breaker: error percentage to trip. Higher in test so a single
      # failure doesn't lock out the whole suite.
      def azure_experiments_v2_resilient_error_threshold_percentage
        GitHub::AppEnvironment.test? ? 50 : 5
      end
    end
  end

  extend Config::AzureExperimentsV2
end
