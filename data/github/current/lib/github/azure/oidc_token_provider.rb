# typed: strict
# frozen_string_literal: true

module GitHub
  module Azure
    # Stateless OIDC token acquisition for Azure AD via workload identity federation.
    # Use this directly when you manage token lifecycle yourself (caching, refresh, fallback).
    # Use WorkloadIdentityTokenClient instead if you need a stateful client with built-in
    # token caching and automatic refresh on expiry.
    class OIDCTokenProvider
      AZURE_STORAGE_TOKEN_SCOPE = "https://storage.azure.com/.default"
      OIDC_CLIENT_ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
      EXPIRATION_SAFE_THRESHOLD_SECONDS = T.let(60, Integer)

      class TokenAcquisitionError < StandardError; end

      module AzureCredentialConfig
        extend T::Helpers

        interface!

        sig { abstract.returns(T.nilable(String)) }
        def azure_client_id; end

        sig { abstract.returns(T.nilable(String)) }
        def azure_tenant_id; end

        sig { abstract.returns(String) }
        def config_name; end
      end

      class TokenResponse < T::Struct
        const :access_token, String
        const :expires_in, Integer
      end

      # Reads the federated JWT from the Kubernetes-projected service account token file.
      # Raises TokenAcquisitionError if the token cannot be read.
      sig { params(federated_token_file: T.nilable(String)).returns(String) }
      def self.read_federated_token(federated_token_file: nil)
        federated_token_file = federated_token_file || ENV["AZURE_FEDERATED_TOKEN_FILE"]

        if federated_token_file.nil?
          raise TokenAcquisitionError, "AZURE_FEDERATED_TOKEN_FILE is not set. " \
            "Ensure the pod has the azure.workload.identity/use: 'true' label."
        end

        token = begin
          File.read(federated_token_file).strip
        rescue SystemCallError => e
          raise TokenAcquisitionError, "Failed to read federated token file #{federated_token_file}: #{e.message}"
        end

        if token.empty?
          raise TokenAcquisitionError, "OIDC token file #{federated_token_file} is empty or contains only whitespace."
        end

        token
      end

      # Acquires an Azure AD token via OIDC workload identity federation.
      # Reads the projected service account token from AZURE_FEDERATED_TOKEN_FILE
      # (injected by the workload identity webhook when the pod has the
      # azure.workload.identity/use label) and exchanges it for an Azure AD token.
      # Client ID and tenant ID come from application config (Vault), not from
      # webhook-injected env vars, so multiple services can share the same pod.
      sig { params(config: AzureCredentialConfig, faraday_client_name: String, scope: String, federated_token_file: T.nilable(String)).returns(TokenResponse) }
      def self.acquire_token(config:, faraday_client_name:, scope:, federated_token_file: nil)
        federated_token = read_federated_token(federated_token_file: federated_token_file)

        client_id = config.azure_client_id
        tenant_id = config.azure_tenant_id

        if client_id.blank? || tenant_id.blank?
          raise TokenAcquisitionError, "Azure SPN client_id or tenant_id is not configured for #{config.config_name}."
        end

        post_token_request(
          tenant_path: tenant_id,
          faraday_client_name: faraday_client_name,
          params: {
            grant_type: "client_credentials",
            client_id: client_id,
            client_assertion_type: OIDC_CLIENT_ASSERTION_TYPE,
            client_assertion: federated_token,
            scope: scope,
          }
        )
      end

      # Exchanges an authorization code for a user-scoped Azure AD token, authenticating
      # the client via OIDC federated credential (client_assertion).
      # Uses the same HTTP infrastructure (FaradayClient.external with proxy/monitoring) as
      # acquire_token, but with grant_type=authorization_code for user-delegated access.
      # The tenant_path controls the {tenant} segment of the token URL (e.g. "organizations"
      # or a specific tenant ID). Defaults to tenant_id if not provided.
      # The federated token is read from federated_token_file when provided; otherwise it
      # falls back to the AZURE_FEDERATED_TOKEN_FILE environment variable.
      sig do
        params(
          client_id: String,
          tenant_id: String,
          scope: String,
          code: String,
          redirect_uri: String,
          faraday_client_name: String,
          tenant_path: T.nilable(String),
          federated_token_file: T.nilable(String)
        ).returns(TokenResponse)
      end
      def self.exchange_authorization_code(client_id:, tenant_id:, scope:, code:, redirect_uri:, faraday_client_name:, tenant_path: nil, federated_token_file: nil)
        federated_token = read_federated_token(federated_token_file: federated_token_file)

        post_token_request(
          tenant_path: tenant_path || tenant_id,
          faraday_client_name: faraday_client_name,
          params: {
            grant_type: "authorization_code",
            client_id: client_id,
            client_assertion_type: OIDC_CLIENT_ASSERTION_TYPE,
            client_assertion: federated_token,
            scope: scope,
            code: code,
            redirect_uri: redirect_uri,
          }
        )
      end

      # Shared HTTP plumbing for all OIDC token requests. Posts form-encoded params
      # to an Azure AD token endpoint via FaradayClient.external.
      # The tenant_path controls the {tenant} segment of the URL — e.g. a specific
      # tenant ID for client_credentials, or "organizations" for authorization_code.
      #
      # Retries: FaradayClient.external installs GitHub::FaradayMiddleware::Retries
      # by default, but its default `methods` list only retries idempotent HTTP
      # verbs (GET/PUT/etc.) and its default `retry_if` only matches Twirp paths.
      # That means a vanilla POST to login.microsoftonline.com is NOT retried,
      # and a single transient timeout or connection failure fails the caller.
      # We override `methods: [:post]` so token-exchange POSTs are retried on
      # the default exception set (Faraday::TimeoutError, Faraday::ConnectionFailed,
      # Errno::ETIMEDOUT, ...) and on the default retry_statuses (502, 503).
      # OAuth 2.0 client_credentials and authorization_code grants are naturally
      # idempotent — each call returns a fresh access token and the server has
      # no side effects beyond rate limiting — so it is safe to retry POSTs here.
      #
      # Resilient: FaradayClient.external also installs the Resilient circuit
      # breaker with `request_volume_threshold: 2` by default, which would trip
      # mid-way through our own 3-attempt retry sequence and convert the third
      # attempt into a synthetic 502 "Resilient: yes" response — defeating the
      # retry benefit and surfacing a confusing error message. We disable
      # Resilient on this connection because there is no useful fallback for
      # a failed token exchange (callers cannot proceed without the token), the
      # retries are short and bounded (~3 attempts, sub-second backoff), and
      # tripping a process-wide breaker on transient noise would cause every
      # other in-flight OIDC caller in the process to fast-fail with a 502
      # for the breaker's sleep window.
      sig { params(tenant_path: String, faraday_client_name: String, params: T::Hash[Symbol, String]).returns(TokenResponse) }
      def self.post_token_request(tenant_path:, faraday_client_name:, params:)
        token_url = URI.parse("https://login.microsoftonline.com/#{tenant_path}/oauth2/v2.0/token")
        connection = GitHub::FaradayClient.external(faraday_client_name, token_url) do |conn|
          conn.use GitHub::FaradayMiddleware::Retries, methods: [:post]
          conn.disable GitHub::FaradayMiddleware::Resilient
        end

        response = begin
          connection.post do |req|
            req.headers["Content-Type"] = "application/x-www-form-urlencoded"
            req.body = URI.encode_www_form(params)
          end
        rescue Faraday::Error => e
          raise TokenAcquisitionError, "OIDC token exchange request failed: #{e.class.name} - #{e.message}"
        end

        unless response.status == 200
          error_code, error_description = begin
            parsed = GitHub::JSON.load(response.body)
            if parsed.is_a?(Hash)
              [parsed["error"] || "unknown", parsed["error_description"]]
            else
              ["unknown", nil]
            end
          rescue Yajl::ParseError => e
            ["unknown (failed to parse response: #{e.message})", nil]
          end
          raise TokenAcquisitionError, "Failed to acquire Azure AD token via OIDC: " \
            "status=#{response.status} error=#{error_code} error_description=#{error_description}"
        end

        response_body = begin
          GitHub::JSON.load(response.body)
        rescue Yajl::ParseError => e
          raise TokenAcquisitionError, "Failed to parse OIDC token response: #{e.message}"
        end

        unless response_body.is_a?(Hash)
          raise TokenAcquisitionError, "OIDC token response is not a JSON object"
        end

        access_token = response_body["access_token"]
        expires_in = response_body["expires_in"]

        if access_token.blank?
          raise TokenAcquisitionError, "OIDC token response missing access_token"
        end

        TokenResponse.new(
          access_token: T.cast(access_token, String),
          expires_in: expires_in.to_i
        )
      end

      private_class_method :post_token_request
    end
  end
end
