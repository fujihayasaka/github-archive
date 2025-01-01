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

      private

      def trino_access_allowed?
        Rails.env.production? || ENV["ALLOW_PRESTO"]
      end

      # Private: Create and return a trino client with RBAC enabled
      def rbac_trino_client
        return NoopTrinoClient.instance unless trino_access_allowed?

        # initialize the token client for trino access
        @token_client ||= GitHub::Azure::AadTokenClient.new(
          tenant_id: GitHub.spn_dotcom_trino_tenant_id,
          client_id: GitHub.spn_dotcom_trino_client_id,
          client_secret: GitHub.spn_dotcom_trino_client_secret,
          object_id: GitHub.spn_dotcom_trino_object_id,
          scope: "#{GitHub.spn_trino_api_endpoint}/.default"
        )

        return @trino unless @trino.nil? || @token_client.token_expired?

        token = @token_client.token

        @trino = ::Trino::Client.new(
          server: "trino.warehouse.service.github.net:443",
          ssl: { verify: true },
          http_headers: {
            "Authorization" => "Bearer #{token}",
          },
          client_info: "secured"
        )

        @trino
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
