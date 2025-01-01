# typed: true
# frozen_string_literal: true

module GitHubModels
  class AzureAiPublishersClient < ApiClient
    PUBLISHERS_ENDPOINT = "/intellectualPropertyPublisher/v1.0/publisherDetails"
    PUBLISHERS_CALL_ERROR_MESSAGE = "Skipping over publisher data in catalog sync"
    SERVICE_NAME = "Azure AI Publishers"

    sig { params(api_url: T.nilable(String)).void }
    def initialize(api_url: nil)
      super(api_url: api_url || GitHub.azure_ai_publishers_url, service_name: SERVICE_NAME)
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def fetch_publishers
      publisher_res = connection.get(PUBLISHERS_ENDPOINT)
      handle_request_error(publisher_res, action: "fetching publishers")
      parse_response_json(res: publisher_res)
    rescue ApiError => e
      GitHub.dogstats.increment("github_models.catalog_sync_failure", tags: ["publisher_data:true"])
      GitHub::Chatterbox.client.say!("#github-models-ops", "Couldn't sync publisher icon information,
        error: #{e.message}")
      GitHub.logger.error(PUBLISHERS_CALL_ERROR_MESSAGE, e.message)
      {}
    end
  end
end
