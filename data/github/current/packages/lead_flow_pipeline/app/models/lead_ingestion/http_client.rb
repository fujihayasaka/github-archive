# typed: true
# frozen_string_literal: true

module LeadIngestion
  class HttpClient
    include GitHub::Memoizer

    def request(method:, slug:, headers: {}, params: {}, body: nil)
      headers["x-ms-correlation-id"] = SecureRandom.uuid.downcase
      azure_http_client.send_request(
        method: method,
        uri: URI.join(api_base_url, slug),
        params: params,
        body: body,
        headers: headers,
      )
    rescue StandardError => e
      GitHub.logger.error("Error making a request in LeadIngestion::HttpClient", {
        :exception       => e,
        "code.namespace" => self.class.name,
        "code.function"  => __method__,
      })
      raise e
    end

    private

    def api_base_url
      GitHub.marketing_forms_lead_ingestion_api_endpoint
    end

    memoize def azure_http_client
      GitHub::Azure::HttpClient.new(token_client: token_client)
    end

    def token_client
      GitHub::Azure::AadTokenClient.new(
        tenant_id: GitHub.marketing_forms_aad_tenant_id,
        client_id: GitHub.marketing_forms_aad_client_id,
        client_secret: GitHub.marketing_forms_aad_client_secret,
        object_id: GitHub.marketing_forms_aad_object_id,
        scope: "#{GitHub.marketing_forms_lead_ingestion_app_resource_id}/.default"
      )
    end
  end
end
