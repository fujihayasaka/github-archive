# typed: true
# frozen_string_literal: true

module Cpm
  class HttpClient
    include GitHub::Memoizer

    DEFAULT_CPM_TIMEOUT_SECONDS = 2

    def request(method:, slug:, headers: {}, params: {}, body: nil, timeout: DEFAULT_CPM_TIMEOUT_SECONDS)
      headers["x-ms-correlation-id"] = SecureRandom.uuid.downcase
      headers["x-ms-filter-topicbrand"] = "GitHub"

      azure_http_client.send_request(
        method: method,
        uri: URI.join(api_base_url, slug),
        params: params,
        body: body,
        headers: headers,
        timeout: timeout,
      )
    rescue StandardError => e
      GitHub.logger.error("Error making a request in Cpm::HttpClient", {
        :exception       => e,
        "code.namespace" => self.class.name,
        "code.function"  => __method__,
      })
      raise e
    end

    private

    def api_base_url
      GitHub.email_preferences_center_cpm_api_url
    end

    memoize def azure_http_client
      GitHub::Azure::HttpClient.new(token_client: token_client)
    end

    def token_client
      # Use workload identity if running in Kubernetes with OIDC token mounted
      # and the feature flag is enabled, otherwise fall back to client secret authentication
      if use_workload_identity?
        GitHub::Azure::WorkloadIdentityTokenClient.new(
          tenant_id: GitHub.email_preferences_center_aad_directory_id,
          client_id: GitHub.email_preferences_center_aad_application_id,
          scope: "#{GitHub.email_preferences_center_cpm_resource_id}/.default"
        )
      else
        GitHub::Azure::AadTokenClient.new(
          tenant_id: GitHub.email_preferences_center_aad_directory_id,
          client_id: GitHub.email_preferences_center_aad_application_id,
          client_secret: GitHub.email_preferences_center_cpm_client_secret,
          object_id: GitHub.email_preferences_center_aad_object_id,
          scope: "#{GitHub.email_preferences_center_cpm_resource_id}/.default"
        )
      end
    end

    def use_workload_identity?
      token_file = ENV["AZURE_FEDERATED_TOKEN_FILE"]
      return false unless token_file
      return false unless File.exist?(token_file)
      return false unless File.readable?(token_file)
      FeatureFlag.vexi.enabled?("cpm_use_azure_workload_identity", default: false)
    end
  end
end
