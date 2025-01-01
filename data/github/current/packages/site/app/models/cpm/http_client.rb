# typed: true
# frozen_string_literal: true

module Cpm
  class HttpClient
    DEFAULT_CPM_TIMEOUT_SECONDS = 2

    def initialize
      token_client = GitHub::Azure::AadTokenClient.new(
        tenant_id: GitHub.cpm_email_preference_center_tenant_id,
        client_id: GitHub.cpm_email_preference_center_client_id,
        client_secret: GitHub.cpm_email_preference_center_client_secret,
        object_id: GitHub.cpm_email_preference_center_object_id,
        scope: "#{GitHub.cpm_email_preference_center_app_resource_id}/.default"
      )
      @http_client = GitHub::Azure::HttpClient.new(token_client: token_client)
    end

    def request(method:, slug:, headers: {}, params: {}, body: nil, timeout: DEFAULT_CPM_TIMEOUT_SECONDS)
      headers["x-ms-correlation-id"] = SecureRandom.uuid.downcase
      headers["x-ms-filter-topicbrand"] = "GitHub"

      @http_client.send_request(
        method: method,
        uri: URI.join(GitHub.cpm_email_preference_center_url, slug),
        params: params,
        body: body,
        headers: headers,
        timeout: timeout,
      )
    end
  end
end
