# typed: true
# frozen_string_literal: true

module LeadIngestion
  class HttpClient
    def initialize
      token_client = GitHub::Azure::AadTokenClient.new(
        tenant_id: GitHub.lead_ingestion_tenant_id,
        client_id: GitHub.lead_ingestion_client_id,
        client_secret: GitHub.lead_ingestion_client_secret,
        object_id: GitHub.lead_ingestion_object_id,
        scope: "#{GitHub.lead_ingestion_app_resource_id}/.default"
      )
      @http_client = GitHub::Azure::HttpClient.new(token_client: token_client)
    end

    def request(method:, slug:, headers: {}, params: {}, body: nil)
      headers["x-ms-correlation-id"] = SecureRandom.uuid.downcase
      @http_client.send_request(
        method: method,
        uri: URI.join(GitHub.lead_ingestion_url, slug),
        params: params,
        body: body,
        headers: headers,
      )
    end
  end
end
