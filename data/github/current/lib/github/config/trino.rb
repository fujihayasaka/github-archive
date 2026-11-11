# typed: true
# frozen_string_literal: true

require "github"
require "trino-client"

module GitHub
  module Config
    # Mixin for the GitHub module that gives access to the trino config
    # and also a memoized GitHub::Trino::Client singleton for presto/trino access.
    module Trino
      # Public: Return the Trino::Client instance
      def trino
        rbac_trino_client
      end

      def trino_oidc
        rbac_trino_client_oidc
      end

      private

      def trino_access_allowed?
        Rails.env.production? || ENV["ALLOW_PRESTO"]
      end

      # Private: Create and return a trino client with RBAC enabled.
      #
      # Uses `build_token_client` to select the authentication strategy based
      # on the `trino_workload_identity_auth` feature flag. The token client is
      # memoized at the process level (`@token_client`), so flag changes take
      # effect on next token refresh (~1 hour) or process restart.
      def rbac_trino_client
        return NoopTrinoClient.instance unless trino_access_allowed?

        @token_client ||= build_token_client

        return @trino unless @trino.nil? || @token_client.token_expired?

        begin
          token = @token_client.token
        rescue GitHub::Azure::OIDCTokenProvider::TokenAcquisitionError => e
          Kernel.raise unless @token_client.is_a?(GitHub::Azure::WorkloadIdentityTokenClient)

          GitHub.logger.warn("trino_workload_identity_token_failed", "gh.error" => e.message)
          GitHub.dogstats.increment("trino.auth.oidc_init_fallback")
          @token_client = aad_token_client
          token = @token_client.token
        end

        @trino = ::Trino::Client.new(
          server: "trino.warehouse.service.github.net:443",
          ssl: { verify: true },
          http_headers: {
            "Authorization" => "Bearer #{token}",
          },
          client_info: "secured",
          source: "dotcom"
        )

        @trino
      end

      # Private: Build the appropriate token client based on feature flag.
      #
      # When `trino_workload_identity_auth` is enabled, uses OIDC-based
      # WorkloadIdentityTokenClient. Falls back to AadTokenClient (client
      # secret) when the flag is disabled.
      def build_token_client
        if FeatureFlag.vexi.enabled?(:trino_workload_identity_auth, default: false)
          GitHub::Azure::WorkloadIdentityTokenClient.new(
            tenant_id: GitHub.spn_dotcom_trino_tenant_id,
            client_id: GitHub.spn_dotcom_trino_client_id,
            scope: "#{GitHub.spn_trino_api_endpoint}/.default"
          )
        else
          aad_token_client
        end
      end

      def aad_token_client
        GitHub::Azure::AadTokenClient.new(
          tenant_id: GitHub.spn_dotcom_trino_tenant_id,
          client_id: GitHub.spn_dotcom_trino_client_id,
          client_secret: GitHub.spn_dotcom_trino_client_secret,
          object_id: GitHub.spn_dotcom_trino_object_id,
          scope: "#{GitHub.spn_trino_api_endpoint}/.default"
        )
      end

      def rbac_trino_client_oidc
        return NoopTrinoClient.instance unless trino_access_allowed?

        @oidc_token_client ||= GitHub::Azure::WorkloadIdentityTokenClient.new(
          tenant_id: GitHub.spn_dotcom_trino_tenant_id,
          client_id: GitHub.spn_dotcom_trino_client_id,
          scope: "#{GitHub.spn_trino_api_endpoint}/.default"
        )

        return @trino_oidc unless @trino_oidc.nil? || @oidc_token_client.token_expired?

        @trino_oidc = ::Trino::Client.new(
          server: "trino.warehouse.service.github.net:443",
          ssl: { verify: true },
          http_headers: { "Authorization" => "Bearer #{@oidc_token_client.token}" },
          client_info: "secured",
          source: "dotcom"
        )
      end

      # A no-op trino client to return results in dev and test.
      class NoopTrinoClient
        include Singleton

        def run(*args)
          [[], []]
        end

        def run_with_names(*args)
          []
        end
      end
    end
  end

  extend Config::Trino
end
