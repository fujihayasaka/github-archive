# typed: true
# frozen_string_literal: true

module GitHubModels
  class AzureAiStudioClient < ApiClient
    MODELS_ENDPOINT = "/asset-gallery/v1.0/models"
    SERVICE_NAME = "Azure AI Studio"

    sig { params(publishers_url: T.nilable(String)).void }
    def initialize(publishers_url: nil)
      super(api_url: GitHub.azure_ai_studio_url, service_name: SERVICE_NAME)
      @publishers_client = AzureAiPublishersClient.new(api_url: publishers_url)
    end

    sig do
      params(
        has_free_playground: T::Boolean,
        publishers: T.nilable(T::Hash[String, T.untyped])
      ).returns(T::Array[T::Hash[Symbol, T.untyped]])
    end
    def fetch_models(has_free_playground: true, publishers: nil)
      payload = request_payload(has_free_playground)
      all_models = []

      continuation_token = T.let("", T.nilable(String))
      has_more_pages = T.let(true, T::Boolean)
      while has_more_pages
        model_res = connection.post(MODELS_ENDPOINT, payload.to_json)
        handle_request_error(model_res, action: "fetching models")

        models = parse_response_json(res: model_res)

        all_models.concat(models["summaries"])
        payload["continuationToken"] = models["continuationToken"]
        has_more_pages = models["continuationToken"].present?
      end

      publishers ||= @publishers_client.fetch_publishers

      to_github_models(models: { "summaries" => all_models }, publishers: publishers)
    end

    sig { params(registry: String, model: String, version: String).returns(T::Hash[Symbol, T.untyped]) }
    def fetch_model_details(registry:, model:, version:)
      raw_res = connection.get("/asset-gallery/v1.0/#{registry}/models/#{model}/version/#{version}")
      handle_request_error(raw_res, action: "fetching model details")

      model_details = parse_response_json(res: raw_res)
      unless model_details.present?
        raise GitHubModels::ApiClient::ApiError.new("There was an error fetching the model details for #{model}")
      end

      to_github_model(model_details, registry)
    end

    private

    # Private: This method is used to parse the response from the model details endpoint.
    sig do
      params(model_json: T::Hash[String, T.untyped], requested_registry: String).returns(T::Hash[Symbol, T.untyped])
    end
    def to_github_model(model_json, requested_registry)
      # TODO: Remove the fallbacks here and error out once API spec has been finalized
      publisher = model_json["publisher"]
      {
        id: model_json["assetId"],
        registry: requested_registry,
        name: model_json["name"].gsub(".", "-"), # Used for URLs/keys
        original_name: model_json["name"],
        friendly_name: model_json["displayName"],
        task: model_json["inferenceTasks"]&.first || "", # This is a list but used to be a String in V1/Nexus
        publisher: model_json["publisher"],
        license: model_json["license"] || "",
        description: model_json["description"],
        summary: model_json["summary"],
        model_version: model_json["version"],
        notes: model_json["notes"],
        popularity: model_json["popularity"],
        tags: model_json["keywords"]&.map { |k| k.downcase.strip },
        rate_limit_tier: model_json.dig("playgroundLimits", "rateLimitTier"),
        supported_languages: model_json.dig("modelLimits", "supportedLanguages") || [],
        max_output_tokens: model_json.dig("modelLimits", "textLimits", "maxOutputTokens"),
        max_input_tokens: model_json.dig("modelLimits", "textLimits", "inputContextWindow") || 0,
        training_data_date: format_training_date(model_json["trainingDataDate"]),
        logo_url: publisher ? "/images/modules/marketplace/models/families/#{publisher.downcase}.svg" : nil,
        dark_mode_icon: model_json["icon_dark"],
        light_mode_icon: model_json["icon_light"],
        evaluation: model_json["evaluation"],
        license_description: model_json["licenseDescription"],
        supported_input_modalities: model_json.dig("modelLimits", "supportedInputModalities")&.map(&:strip) || [],
        supported_output_modalities: model_json.dig("modelLimits", "supportedOutputModalities")&.map(&:strip) || [],
      }
    end

    # This method is used to parse the response from the Azure Catalog List endpoint
    sig do
      params(models: T::Hash[String, T.untyped], publishers: T::Hash[String, T.untyped])
        .returns(T::Array[T::Hash[Symbol, T.untyped]])
    end
    def to_github_models(models:, publishers:)
      # Models are nested under the "summaries" key in the JSON response
      models = models["summaries"]
      publishers = publishers.fetch("value", []).each_with_object({}) do |publisher, acc|
        acc[publisher["publisherName"]] = {
          "icon_dark" => publisher["iconDark"],
          "icon_light" => publisher["iconLight"],
        }
        acc
      end

      models.map do |model|
        publisher_data = publishers.fetch(model["publisher"], {})

        # We could just return the raw response from the models list endpoint here,
        # but I'd like to prevent against the API changing from underneath or feet
        # and returning random data.
        T.let({
          id: model["assetId"],
          registry: model["registryName"], # Used to fetch details
          name: model["name"].gsub(".", "-"),
          original_name: model["name"], # Used to fetch details
          friendly_name: model["displayName"],
          task: model["inferenceTasks"]&.first, # This is a list but used to be a String in V1/Nexus
          publisher: model["publisher"],
          license: model["license"],
          description: "", # In Details response
          summary: model["summary"] || "",
          model_version: model["version"],
          model_capabilities: model["modelCapabilities"] || [],
          notes: "", # In Details response
          popularity: model["popularity"],
          tags: [], # In Details response as keywords
          rate_limit_tier: nil,
          supported_languages: [],
          max_output_tokens: nil,
          max_input_tokens: 0,
          training_data_date: "",
          logo_url: "/images/modules/marketplace/models/families/#{model["publisher"].downcase}.svg",
          dark_mode_icon: publisher_data["icon_dark"],
          light_mode_icon: publisher_data["icon_light"],
          evaluation: "", # In Details response
          license_description: "", # In Details response
          supported_input_modalities: [],
          supported_output_modalities: [],
        }, T::Hash[Symbol, T.untyped])
      end
    end

    sig { params(has_free_playground: T::Boolean).returns(T::Hash[T.untyped, T.untyped]) }
    def request_payload(has_free_playground)
      payload = {
        "pageSize": 100,
        "filters": [{ "field": "labels", "values": ["latest"], "operator": "eq" }],
        "order": [{ "field": "displayName", "direction": "Asc" }],
      }
      if has_free_playground
        payload[:filters].push({ "field": "freePlayground", "values": ["true"], "operator": "eq" })
      end
      payload
    end

    # Formats the training date from 2023-10-01T00:00:00+00:00 to Oct 2023
    sig { params(datetime_string: T.nilable(String)).returns(T.nilable(String)) }
    def format_training_date(datetime_string)
      DateTime.parse(datetime_string).strftime("%b %Y") if datetime_string
    end
  end
end
