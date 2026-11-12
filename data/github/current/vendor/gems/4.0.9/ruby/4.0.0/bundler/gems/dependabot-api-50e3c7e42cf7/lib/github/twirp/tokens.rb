# typed: true
# frozen_string_literal: true

require "twirp"

module GitHub
  module Twirp
    class Tokens
      class Error < StandardError; end

      JitAccessResponse = Struct.new(:token, :repository_id)

      DEFAULT_PERMISSIONS = { contents: "read", metadata: "read" }.freeze

      extend T::Sig

      sig do
        params(
          client: T.any(Twirp::Client, MonolithTwirp::Dependabot::Tokens::V1::TokenAPIClient),
          tenant: T.any(Tenant, NullTenant)
        ).void
      end
      def initialize(client:, tenant:)
        @client = client
        @tenant = tenant
      end

      sig do
        params(
          account_name: String,
          repo_name: String,
          permissions: T::Hash[T.any(Symbol, String), String]
        ).returns(JitAccessResponse)
      end
      def create_jit_access(account_name:, repo_name:, permissions: DEFAULT_PERMISSIONS)
        response = log_timing do
          tokens_api.create_jit_access(
            MonolithTwirp::Dependabot::Tokens::V1::CreateJitAccessRequest.new(
              account_name:,
              repo_name:,
              permissions:
            ),
            headers
          )
        end

        if response.error.present?
          error = response.error
          Dependabot::Logger.error(
            msg: error.msg,
            error_code: error.code,
            error_metadata: error.meta,
          )

          raise Error, "#{error.msg} - #{error.meta}"
        end

        JitAccessResponse.new(token: response.data.token, repository_id: response.data.repository_id)
      end

      private

      sig { returns(T::Hash[String, String]) }
      def headers
        return {} unless Dependabot.proxima?
        raise GitHub::Twirp::Error, "Required Proxima tenant not set" if @tenant.slug.blank?

        {
          headers: { "X-GitHub-Tenant" => @tenant.slug },
        }
      end

      def log_timing
        start_time = Time.now.in_time_zone
        response = yield
        duration = Time.now.in_time_zone - start_time

        method_name = caller_locations(1, 1)&.first&.label || "unknown"
        MetricsClient.distribution(
          "twirp.github.tokens.#{method_name}",
          duration,
          tags: { response_code: response&.error&.code || :ok }
        )

        response
      end

      sig { returns(MonolithTwirp::Dependabot::Tokens::V1::TokenAPIClient) }
      def tokens_api
        @tokens_api ||=
          if @client.is_a?(MonolithTwirp::Dependabot::Tokens::V1::TokenAPIClient)
            @client
          else
            MonolithTwirp::Dependabot::Tokens::V1::TokenAPIClient.new(@client.connection)
          end
      end
    end
  end
end
