# typed: strict
# frozen_string_literal: true

module GitHub
  module Azure
    # Token client for Azure Workload Identity (federated credentials) authentication.
    # Uses OIDC tokens mounted by Kubernetes to authenticate to Azure AD.
    # For client secret authentication, use AadTokenClient instead.
    class WorkloadIdentityTokenClient

      # Will renew the token within this number of seconds before it expires
      EXPIRATION_SAFE_THRESHOLD_SECONDS = 60
      HEADERS = T.let({ "Content-Type" => "application/x-www-form-urlencoded" }, T::Hash[T.untyped, T.untyped])

      sig { params(tenant_id: String, client_id: String, scope: String).void }
      def initialize(tenant_id:, client_id:, scope:)
        @token_url = T.let("https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token", String)
        @client_id = client_id
        @scope = scope
        @http_client = T.let(GitHub::Azure::HttpClient.new, GitHub::Azure::HttpClient)
        @federated_token_file = T.let(ENV["AZURE_FEDERATED_TOKEN_FILE"], T.nilable(String))

        validate_configuration!
      end

      sig { returns(String) }
      def token
        requested_at = Time.now.to_i
        if @token.nil? || requested_at >= T.must(@token_expires_at)
          @token = T.let(fetch_token, T.nilable(T::Hash[Symbol, T.untyped]))
          @token_expires_at = T.let(requested_at + T.must(@token)[:expires_in] - EXPIRATION_SAFE_THRESHOLD_SECONDS, T.nilable(Integer))
        end
        T.must(@token)[:access_token]
      end

      sig { returns(T::Boolean) }
      def token_expired?
        return true if @token.nil?
        Time.now.to_i >= T.must(@token_expires_at)
      end

      private

      sig { void }
      def validate_configuration!
        if @federated_token_file.nil? || @federated_token_file.empty?
          raise ArgumentError, "AZURE_FEDERATED_TOKEN_FILE environment variable must be set"
        elsif !File.exist?(@federated_token_file)
          raise ArgumentError, "Federated token file does not exist: #{@federated_token_file}"
        end
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def fetch_token
        oidc_token = fetch_oidc_token
        if oidc_token.nil? || oidc_token.strip.empty?
          raise ArgumentError, "OIDC token file #{@federated_token_file} is empty or contains only whitespace"
        end

        request_body = URI.encode_www_form({
          "grant_type" => "client_credentials",
          "client_id" => @client_id,
          "client_assertion_type" => "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
          "client_assertion" => oidc_token,
          "scope" => @scope
        })

        response = @http_client.send_request(
          method: :post,
          uri: @token_url,
          body: request_body,
          headers: HEADERS
        )
        response.body
      end

      sig { returns(T.nilable(String)) }
      def fetch_oidc_token
        return nil unless @federated_token_file && File.exist?(@federated_token_file)
        File.read(@federated_token_file).strip
      end
    end
  end
end
