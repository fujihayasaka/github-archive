# typed: true
# frozen_string_literal: true

module GitHub
  module Azure
    class KeyVaultClient

      API_VERSION = "7.1"
      OAUTH_SCOPE = "https://vault.azure.net/.default"

      def initialize(tenant_id:, client_id:, client_secret:, object_id:, vault_name:)
        raise ArgumentError, "tenant_id cannot be blank" if tenant_id.blank?
        raise ArgumentError, "client_id cannot be blank" if client_id.blank?
        raise ArgumentError, "client_secret cannot be blank" if client_secret.blank?
        raise ArgumentError, "object_id cannot be blank" if object_id.blank?
        raise ArgumentError, "vault_name cannot be blank" if vault_name.blank?

        token_client = GitHub::Azure::AadTokenClient.new(
          tenant_id: tenant_id,
          client_id: client_id,
          client_secret: client_secret,
          object_id: object_id,
          scope: OAUTH_SCOPE
        )
        @http_client = GitHub::Azure::HttpClient.new(token_client: token_client)
        @vault_name = vault_name
      end

      def get_secret(secret_name)
        response = @http_client.send_request(method: :get,
          uri: "https://#{@vault_name}.vault.azure.net/secrets/#{secret_name}?api-version=#{API_VERSION}"
        )
        parse_response(response.body)
      end

      # Returns a hash for use within the application
      # Hash is of the format :
      # {
      # value: "<the actual value of the secret>",
      # expiry: "<when the secret is set to expire>",
      # }
      def parse_response(response_body)
        # The response from Azure Key Vault is of this format:
        # {
        #   "value": "<some-value>",
        #   "contentType": "application/vnd.ms-sastoken-storage",
        #   "id": "https://billingnonprod573dad.vault.azure.net/secrets/billingnonprod573dad-pav2sas",
        #   "managed": true,
        #   "attributes": {
        #     "enabled": true,
        #     "exp": 1601729845,
        #     "recoveryLevel": "Recoverable+Purgeable",
        #     "recoverableDays": 90
        #   }
        # }

        h = {
          value: response_body[:value],
          expiry: T.let(nil, T.nilable(DateTime))
        }

        if response_body[:attributes] && !!response_body[:attributes][:enabled]
          expiry_epoch = response_body[:attributes][:exp].to_s
          h[:expiry] = DateTime.strptime(expiry_epoch, "%s")
        end
        h
      end
    end
  end
end
