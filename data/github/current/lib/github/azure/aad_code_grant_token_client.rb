# typed: false
# frozen_string_literal: true

module GitHub
  module Azure
    class AadCodeGrantTokenClient
      # Will renew the token within this number of seconds before it expires
      EXPIRATION_SAFE_THRESHOLD_SECONDS = 60
      HEADERS = { "Content-Type" => "application/x-www-form-urlencoded" }.freeze
      GRAPH_SCOPE = "https://graph.microsoft.com/.default"

      # Exchanges an authorization code for an Azure AD token.
      #
      # Two client authentication modes, determined by whether client_secret is provided:
      # - With client_secret: uses the legacy HttpClient with a shared secret.
      # - Without client_secret (OIDC): delegates to OIDCTokenProvider.exchange_authorization_code,
      #   which reads the federated credential from AZURE_FEDERATED_TOKEN_FILE and uses
      #   FaradayClient.external with proxy/monitoring middleware. Requires tenant_id.
      #
      # In both modes the token endpoint defaults to /organizations/ unless a
      # tenant_path is provided to scope sign-in to a specific tenant.
      def initialize(client_id:, scope:, redirect_uri:, code:, client_secret: nil, tenant_id: nil, tenant_path: nil)
        if client_secret.nil? && tenant_id.blank?
          raise ArgumentError, "tenant_id is required when using OIDC (no client_secret provided)"
        end

        @token_url = "https://login.microsoftonline.com/#{tenant_path || "organizations"}/oauth2/v2.0/token"
        @client_id = client_id
        @client_secret = client_secret
        @tenant_id = tenant_id
        @tenant_path = tenant_path
        @scope = scope
        @redirect_uri = redirect_uri
        @code = code

        @http_client = GitHub::Azure::HttpClient.new if client_secret
      end

      def fetch_token
        if client_secret
          fetch_token_via_client_secret
        else
          fetch_token_via_oidc
        end
      end

      private

      attr_reader :token_url, :client_id, :client_secret, :tenant_id, :tenant_path, :scope, :redirect_uri, :code, :http_client
      attr_accessor :token

      def fetch_token_via_oidc
        result = GitHub::Azure::OIDCTokenProvider.exchange_authorization_code(
          client_id: client_id,
          tenant_id: tenant_id,
          scope: scope,
          code: code,
          redirect_uri: redirect_uri,
          faraday_client_name: "AadCodeGrantTokenClient",
          tenant_path: tenant_path,
          federated_token_file: ENV["AZURE_FEDERATED_TOKEN_FILE_SHORT"]
        )
        result.access_token
      end

      # Legacy client_secret path: preserves existing behavior using GitHub::Azure::HttpClient.
      def fetch_token_via_client_secret
        requested_at = Time.now.to_i
        if token.nil? || requested_at >= token_expires_at
          self.token = http_client.send_request(method: :post,
            uri: token_url,
            body: request_body(scope),
            headers: HEADERS
          ).body
        end
        self.token[:access_token]
      end

      def token_expires_at
        return 0 if token.nil?
        token[:expires_on].to_i - EXPIRATION_SAFE_THRESHOLD_SECONDS
      end

      def request_body(scope)
        URI.encode_www_form({
          "grant_type" => "authorization_code",
          "client_id" => client_id,
          "client_secret" => client_secret,
          "scope" => scope,
          "redirect_uri" => redirect_uri,
          "code" => code,
        })
      end
    end
  end
end
