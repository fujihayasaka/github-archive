# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module RateLimits
      API_UNAUTHENTICATED_RATE_LIMIT          = 60      # per hour
      API_DEFAULT_RATE_LIMIT                  = 5000    # per hour
      API_ENTERPRISE_CLOUD_SOFT_RATE_LIMIT    = 15_000  # per hour
      API_ENTERPRISE_CLOUD_HARD_RATE_LIMIT    = 15_000  # per hour
      API_TIER_ONE_RATE_LIMIT                 = 12500   # per hour
      API_TIER_TWO_RATE_LIMIT                 = 62500   # per hour
      API_SEARCH_UNAUTHENTICATED_RATE_LIMIT   = 10      # per minute
      API_SEARCH_DEFAULT_RATE_LIMIT           = 30      # per minute
      API_AUDIT_LOG_UNAUTHENTICATED_RATE_LIMIT = 0           # per minute
      API_AUDIT_LOG_DEFAULT_RATE_LIMIT = 1750                # per hour
      API_AUDIT_LOG_STREAMING_UNAUTHENTICATED_RATE_LIMIT = 0 # per minute
      API_AUDIT_LOG_STREAMING_DEFAULT_RATE_LIMIT = 15        # per hour
      API_CODE_SEARCH_UNAUTHENTICATED_RATE_LIMIT = 0    # per minute
      API_CODE_SEARCH_DEFAULT_RATE_LIMIT = 10      # per minute
      API_CODE_SEARCH_ENTERPRISE_CLOUD_HARD_RATE_LIMIT = 100 # per minute
      API_SEARCH_ENTERPRISE_CLOUD_HARD_RATE_LIMIT = 100 # per minute
      API_LFS_UNAUTHENTICATED_RATE_LIMIT      = 100     # per minute
      API_LFS_DEFAULT_RATE_LIMIT              = 3000    # per minute
      API_INTEGRATION_MANIFEST_UNAUTHENTICATED_RATE_LIMIT = 5_000  # per hour
      API_GRAPHQL_UNAUTHENTICATED_RATE_LIMIT  = 0       # per hour
      API_GRAPHQL_DEFAULT_RATE_LIMIT          = 5_000   # per hour
      API_GRAPHQL_HIGHER_RATE_LIMIT           = 10_000  # per hour
      API_GRAPHQL_MUCH_HIGHER_RATE_LIMIT      = 50_000  # per hour
      API_GRAPHQL_ENTERPRISE_CLOUD_HARD_RATE_LIMIT = 10_000 # per hour
      API_CODE_SCANNING_UPLOAD_RATE_LIMIT = 1000    # per hour
      API_CODE_SCANNING_VARIANT_ANALYSIS_UPDATE_RATE_LIMIT = 15_000 # per hour
      API_CODESPACES_LIMIT = 5000    # per hour
      API_ACTIONS_RUNNER_REGISTRATION_RATE_LIMIT = 10000  # per hour
      API_DEPENDENCY_SNAPSHOTS_RATE_LIMIT     = 100 # per minute
      # The default API rate limit for non authenticated requests.
      #
      # Returns the rate limit integer value. Defaults to 60/hr
      def api_unauthenticated_rate_limit
        @api_unauthenticated_rate_limit || API_UNAUTHENTICATED_RATE_LIMIT
      end
      attr_writer :api_unauthenticated_rate_limit

      # The default API rate limit for non allowlisted apps.
      #
      # Returns the rate limit integer value. Defaults to 5000
      def api_default_rate_limit
        @api_default_rate_limit || API_DEFAULT_RATE_LIMIT
      end
      attr_writer :api_default_rate_limit

      def api_enterprise_cloud_soft_rate_limit
        @api_enterprise_cloud_soft_rate_limit || API_ENTERPRISE_CLOUD_SOFT_RATE_LIMIT
      end
      attr_writer :api_enterprise_cloud_soft_rate_limit

      def api_enterprise_cloud_hard_rate_limit
        @api_enterprise_cloud_hard_rate_limit || API_ENTERPRISE_CLOUD_HARD_RATE_LIMIT
      end
      attr_writer :api_enterprise_cloud_hard_rate_limit

      # Some Oauth apps get more API calls per hour. This is
      # the default value for apps at this first tier.
      #
      # Returns the rate limit integer value. Defaults to 300000/day
      def api_tier_one_rate_limit
        @api_tier_one_rate_limit || API_TIER_ONE_RATE_LIMIT
      end
      attr_writer :api_tier_one_rate_limit

      # Some Oauth apps get an obscene amount of API calls per hour. This is
      # the default value for apps at this top tier.
      #
      # Returns the rate limit integer value. Defaults to 1.5m/day
      def api_tier_two_rate_limit
        @api_tier_two_rate_limit || API_TIER_TWO_RATE_LIMIT
      end
      attr_writer :api_tier_two_rate_limit

      # The default Search API rate limit for authenticated requests.
      #
      # Returns the rate limit integer value.  Defaults to 30/min
      def api_search_default_rate_limit
        @api_search_default_rate_limit || API_SEARCH_DEFAULT_RATE_LIMIT
      end
      attr_writer :api_search_default_rate_limit

      def api_search_enterprise_cloud_hard_rate_limit
        @api_search_enterprise_cloud_hard_rate_limit || API_SEARCH_ENTERPRISE_CLOUD_HARD_RATE_LIMIT
      end
      attr_writer :api_search_enterprise_cloud_hard_rate_limit

      # The default Search API rate limit for non authenticated requests.
      #
      # Returns the rate limit integer value.  Defaults to 10/minute
      def api_search_unauthenticated_rate_limit
        @api_search_unauthenticated_rate_limit || API_SEARCH_UNAUTHENTICATED_RATE_LIMIT
      end
      attr_writer :api_search_unauthenticated_rate_limit

      # The default Audit Log API rate limit
      #
      # Returns the rate limit integer value. Defaults to 50/minute
      def api_audit_log_default_rate_limit
        @api_audit_log_default_rate_limit || API_AUDIT_LOG_DEFAULT_RATE_LIMIT
      end
      attr_writer :api_audit_log_default_rate_limit

      # The default Audit Log API rate limit for non authenticated requests.
      #
      # Returns the rate limit integer value. Defaullts to 0/minute
      def api_audit_log_unauthenticated_rate_limit
        @api_audit_log_unauthenticated_rate_limit || API_AUDIT_LOG_UNAUTHENTICATED_RATE_LIMIT
      end
      attr_writer :api_audit_log_unauthenticated_rate_limit

      # The default Audit Log Streaming API rate limit
      #
      # Returns the rate limit integer value. Defaults to 50/minute
      def api_audit_log_streaming_default_rate_limit
        @api_audit_log_streaming_default_rate_limit || API_AUDIT_LOG_STREAMING_DEFAULT_RATE_LIMIT
      end
      attr_writer :api_audit_log_streaming_default_rate_limit

      # The default Audit Log Streaming API rate limit for non authenticated requests.
      #
      # Returns the rate limit integer value. Defaullts to 0/minute
      def api_audit_log_streaming_unauthenticated_rate_limit
        @api_audit_log_streaming_unauthenticated_rate_limit || API_AUDIT_LOG_STREAMING_UNAUTHENTICATED_RATE_LIMIT
      end
      attr_writer :api_audit_log_streaming_unauthenticated_rate_limit


      # The default Code Search API rate limit for non authenticated requests.
      #
      # Returns the rate limit integer value.  Defaults to 10/minute
      def api_code_search_unauthenticated_rate_limit
        @api_code_search_unauthenticated_rate_limit || API_CODE_SEARCH_UNAUTHENTICATED_RATE_LIMIT
      end
      attr_writer :api_code_search_unauthenticated_rate_limit

      # The default Code Search API rate limit
      #
      # Returns the rate limit integer value.
      def api_code_search_default_rate_limit
        @api_code_search_default_rate_limit || API_CODE_SEARCH_DEFAULT_RATE_LIMIT
      end
      attr_writer :api_code_search_default_rate_limit

      # The default Code Search API rate limit for non authenticated requests.
      #
      # Returns the rate limit integer value.  Defaults to 10/minute
      def api_code_search_enterprise_cloud_hard_rate_limit
        @api_code_search_enterprise_cloud_hard_rate_limit || API_CODE_SEARCH_ENTERPRISE_CLOUD_HARD_RATE_LIMIT
      end
      attr_writer :api_code_search_enterprise_cloud_hard_rate_limit

      # The default LFS API rate limit for non authenticated requests.
      #
      # Returns the rate limit integer value.  Defaults to 100/minute
      def api_lfs_unauthenticated_rate_limit
        @api_lfs_unauthenticated_rate_limit || API_LFS_UNAUTHENTICATED_RATE_LIMIT
      end
      attr_writer :api_lfs_unauthenticated_rate_limit

      # The default LFS API rate limit for authenticated requests.
      #
      # Returns the rate limit integer value.  Defaults to 3000/minute
      def api_lfs_default_rate_limit
        @api_lfs_default_rate_limit || API_LFS_DEFAULT_RATE_LIMIT
      end
      attr_writer :api_lfs_default_rate_limit

      # The default app manifest API rate limit for authenticated requests.
      #
      # Returns the rate limit integer value.
      def api_integration_manifest_unauthenticated_rate_limit
        @api_integration_manifest_unauthenticated_rate_limit || API_INTEGRATION_MANIFEST_UNAUTHENTICATED_RATE_LIMIT
      end
      attr_writer :api_integration_manifest_unauthenticated_rate_limit

      # The default GraphQL API rate limit for non authenticated requests.
      #
      # Returns the rate limit integer value.  Defaults to 0/hour
      def api_graphql_unauthenticated_rate_limit
        @api_graphql_unauthenticated_rate_limit || API_GRAPHQL_UNAUTHENTICATED_RATE_LIMIT
      end
      attr_writer :api_graphql_unauthenticated_rate_limit

      # The default GraphQL API rate limit for authenticated requests.
      #
      # Returns the rate limit integer value.  Defaults to 5000/hour
      def api_graphql_default_rate_limit
        @api_graphql_default_rate_limit || API_GRAPHQL_DEFAULT_RATE_LIMIT
      end
      attr_writer :api_graphql_default_rate_limit

      # The higher GraphQL API rate limit for allowlisted clients.
      #
      # Returns the rate limit integer value.  Defaults to 10,000/hour
      def api_graphql_higher_rate_limit
        @api_graphql_higher_rate_limit || API_GRAPHQL_HIGHER_RATE_LIMIT
      end
      attr_writer :api_graphql_higher_rate_limit

      # The much higher GraphQL API rate limit for allowlisted clients that are GitHub staff.
      #
      # Returns the rate limit integer value.  Defaults to 50,000/hour
      def api_graphql_much_higher_rate_limit
        @api_graphql_much_higher_rate_limit || API_GRAPHQL_MUCH_HIGHER_RATE_LIMIT
      end
      attr_writer :api_graphql_much_higher_rate_limit

      def api_graphql_enterprise_cloud_hard_rate_limit
        @api_graphql_enterprise_cloud_hard_rate_limit || API_GRAPHQL_ENTERPRISE_CLOUD_HARD_RATE_LIMIT
      end
      attr_writer :api_graphql_enterprise_cloud_hard_rate_limit

      # The API rate limit for code scanning uploads.
      #
      # Returns the rate limit integer value.  Defaults to 1000/hour
      def api_code_scanning_upload_rate_limit
        @api_code_scanning_upload_rate_limit || API_CODE_SCANNING_UPLOAD_RATE_LIMIT
      end
      attr_writer :api_code_scanning_upload_rate_limit

      # The API rate limit for code scanning variant analysis updates.
      #
      # Returns the rate limit integer value.  Defaults to 15,000/hour
      def api_code_scanning_variant_analysis_update_rate_limit
        @api_code_scanning_variant_analysis_update_rate_limit || API_CODE_SCANNING_VARIANT_ANALYSIS_UPDATE_RATE_LIMIT
      end
      attr_writer :api_code_scanning_variant_analysis_update_rate_limit

      def api_codespaces_limit
        @api_codespaces_limit || API_CODESPACES_LIMIT
      end
      attr_writer :api_codespaces_limit

      # The API rate limit for runner registration calls
      #
      # Returns the rate limit integer value.  Defaults to 10000/hour
      def api_actions_runner_registration_rate_limit
        @api_actions_runner_registration_rate_limit || API_ACTIONS_RUNNER_REGISTRATION_RATE_LIMIT
      end
      attr_writer :api_actions_runner_registration_rate_limit

      # The API rate limit for Dependency Snapshots API calls.
      #
      # Returns the rate limit integer value. Defaults to 100/minute, but can be set to 5/minute
      # in an emergency with `dependency_graph_snapshots_rate_limit_circuit_breaker`.
      def api_dependency_snapshots_rate_limit
        return @api_dependency_snapshots_rate_limit if @api_dependency_snapshots_rate_limit
        if GitHub.flipper[:dependency_graph_snapshots_rate_limit_circuit_breaker].enabled?
          5
        else
          API_DEPENDENCY_SNAPSHOTS_RATE_LIMIT
        end
      end
      attr_writer :api_dependency_snapshots_rate_limit
    end
  end

  extend Config::RateLimits
end
