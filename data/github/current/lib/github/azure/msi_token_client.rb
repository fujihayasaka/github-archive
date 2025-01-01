# typed: true
# frozen_string_literal: true

module GitHub
  module Azure

    # Used to obtain an access token using managed identities for Azure resources on an Azure VM.
    # See https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/how-to-use-vm-token for more information.
    class MsiTokenClient

      # Will renew the token within this number of seconds before it expires, we expect tokens to last an hour
      EXPIRATION_SAFE_THRESHOLD_SECONDS = 60
      HEADERS = { "Metadata" => "true" }
      API_VERSION = "2018-02-01"
      BASE_TOKEN_URL = "http://169.254.169.254/metadata/identity/oauth2/token" # This is a magic IP available to Azure VMs

      # Requires a resource and at most one of client_id:, msi_res_id:, or object_id: as per
      # https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/how-to-use-vm-token#get-a-token-using-http
      def initialize(resource_id_uri, **kwargs)
        unless kwargs.size == 0 || (kwargs.size == 1 && [:client_id, :msi_res_id, :object_id].include?(kwargs.keys.first))
          raise ArgumentError, "Must provide at most one of 'client_id', 'msi_res_id', or 'object_id'"
        end
        query_hash = {
          "api-version": API_VERSION,
          resource: resource_id_uri,
        }.merge(kwargs)

        @token_url = "#{BASE_TOKEN_URL}?#{query_hash.to_query}"
        @http_client = GitHub::Azure::HttpClient.new
      end

      def token
        requested_at = Time.now.to_i
        if @token.nil? || requested_at >= @token_expires_at
          @token = @http_client.send_request(method: :get,
            uri: @token_url,
            headers: HEADERS,
          ).body
          @token_expires_at = requested_at + @token[:expires_in].to_i - EXPIRATION_SAFE_THRESHOLD_SECONDS
        end
        @token[:access_token]
      end
    end
  end
end
