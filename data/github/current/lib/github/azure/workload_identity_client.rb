# typed: strict
# frozen_string_literal: true

module GitHub
  module Azure
    # Stateful token client for Azure Workload Identity (federated credentials) authentication.
    # Wraps OIDCTokenProvider with built-in token caching and automatic renewal.
    # Uses OIDC tokens mounted by Kubernetes to authenticate to Azure AD.
    # For client secret authentication, use AadTokenClient instead.
    class WorkloadIdentityTokenClient
      class Config < T::Struct
        include GitHub::Azure::OIDCTokenProvider::AzureCredentialConfig

        const :client_id, T.nilable(String)
        const :tenant_id, T.nilable(String)
        const :name, String, default: "workload_identity"

        sig { override.returns(T.nilable(String)) }
        def azure_client_id
          client_id
        end

        sig { override.returns(T.nilable(String)) }
        def azure_tenant_id
          tenant_id
        end

        sig { override.returns(String) }
        def config_name
          name
        end
      end

      sig { params(tenant_id: String, client_id: String, scope: String, federated_token_file: T.nilable(String)).void }
      def initialize(tenant_id:, client_id:, scope:, federated_token_file: nil)
        @config = T.let(Config.new(client_id: client_id, tenant_id: tenant_id), Config)
        @scope = scope
        @federated_token_file = T.let(federated_token_file, T.nilable(String))
        @access_token = T.let(nil, T.nilable(String))
        @token_expires_at = T.let(nil, T.nilable(Integer))
      end

      sig { returns(String) }
      def token
        now = Time.now.to_i
        if @access_token.nil? || @token_expires_at.nil? || now >= @token_expires_at
          result = GitHub::Azure::OIDCTokenProvider.acquire_token(
            config: @config,
            faraday_client_name: "WorkloadIdentityTokenClient",
            scope: @scope,
            federated_token_file: @federated_token_file,
          )
          @access_token = result.access_token
          @token_expires_at = now + result.expires_in - OIDCTokenProvider::EXPIRATION_SAFE_THRESHOLD_SECONDS
        end

        @access_token
      end

      sig { returns(T::Boolean) }
      def token_expired?
        return true if @access_token.nil? || @token_expires_at.nil?
        Time.now.to_i >= @token_expires_at
      end
    end
  end
end
