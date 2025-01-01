# typed: true
# frozen_string_literal: true

module GitHubModels
  module Client
    include GitHubModels::Parseable

    MODELS_ENDPOINT = "/asset-gallery/v1.0/models"
    PUBLISHERS_ENDPOINT = "/intellectualPropertyPublisher/v1.0/publisherDetails"
    PUBLISHERS_CALL_ERROR_MESSAGE = "Skipping over publisher data in catalog sync"

    # This is a temporary mapping to allow us to launch models that don't have entries in the schema yet.
    # Keys and values must be in the format registry/model_name.downcase
    SCHEMA_MAPPING = {
      "azureml/phi-4-multimodal-instruct" => "azureml/phi-3.5-vision-instruct"
    }

    class ApiError < StandardError; end

    sig { params(has_free_playground: T::Boolean, publishers: T.nilable(T::Hash[String, T.untyped])).returns(T::Array[GitHubModels::Types::Model]) }
    def self.fetch_models(has_free_playground: true, publishers: nil)
      payload = request_payload(has_free_playground)
      connection = new_connection(GitHub.azure_ai_studio_url)
      all_models = []

      continuation_token = T.let("", T.nilable(String))
      has_more_pages = T.let(true, T::Boolean)
      while has_more_pages
        model_res = connection.post(MODELS_ENDPOINT, payload.to_json)
        handle_request_error(model_res)

        models = parse_response_json(res: model_res, service_name: "Azure Models")

        all_models.concat(models["summaries"])
        payload["continuationToken"] = models["continuationToken"]
        has_more_pages = models["continuationToken"].present?
      end

      publishers ||= self.fetch_publishers

      to_github_models(models: { "summaries" => all_models }, publishers: publishers)
    end

    sig { params(publishers_url: String).returns(T::Hash[String, T.untyped]) }
    def self.fetch_publishers(publishers_url: GitHub.azure_ai_publishers_url)
      publisher_res = new_connection(publishers_url)
        .get(PUBLISHERS_ENDPOINT)
      self.handle_request_error(publisher_res)

      parse_response_json(res: publisher_res, service_name: "Publishers")
      rescue ApiError => e
        GitHub.dogstats.increment("github_models.catalog_sync_failure", tags: ["publisher_data:true"])
        GitHub::Chatterbox.client.say!("#github-models-ops", "Couldn't sync publisher icon information, error: #{e.message}")
        GitHub.logger.error(PUBLISHERS_CALL_ERROR_MESSAGE, e.message)
        {}
    end

    sig do
      params(registry: String, model_name: String, version: String).returns(GitHubModels::Types::RenderableModel)
    end
    def self.fetch_model(registry:, model_name:, version:)
      model = fetch_model_details(registry:, model: model_name, version:)
      schema = fetch_model_schema(registry:, model: model_name)

      unless model.present? && schema.present?
        raise ApiError.new("There was an error fetching either the model or schema for #{model_name}")
      end

      {
        model: model,
        schema: schema
      }
    end

    sig { params(registry: String, model: String, version: String).returns(GitHubModels::Types::Model) }
    def self.fetch_model_details(registry:, model:, version:)
      raw_res = new_connection(GitHub.azure_ai_studio_url)
        .get("/asset-gallery/v1.0/#{registry}/models/#{model}/version/#{version}")
      self.handle_request_error(raw_res)
      model_details = parse_response_json(res: raw_res, service_name: "Model Details")

      to_github_model(model_details, registry)
    end

    sig { params(registry: String, model: String).returns(GitHubModels::Types::ModelSchema) }
    def self.fetch_model_schema(registry:, model:)

      # We need to launch some models that don't have entries in the schema yet. This allows us to
      # substitute a schema from a model that does exist
      url_registry, url_model = if SCHEMA_MAPPING["#{registry}/#{model.downcase}"].present?
        SCHEMA_MAPPING["#{registry}/#{model.downcase}"].split("/")
      else
        [registry, model.downcase]
      end

      raw_res = new_connection(GitHub.azure_ai_model_schema_url)
        .get("/widgets/en/Serverless/#{url_registry}/#{url_model}.json")
      self.handle_request_error(raw_res)
      schema_details = parse_response_json(res: raw_res, service_name: "Model Schema")

      to_model_schema(schema_details)
    end

    sig { params(url: String).returns(::GitHub::FaradayClient::External) }
    def self.new_connection(url)
      ::GitHub::FaradayClient::External.new(url) do |conn|
        conn.options[:open_timeout] = 2
        conn.options[:timeout] = 5
        conn.headers[:content_type] = "application/json"

        conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: GitHub::Config::Models::SERVICE_NAME
        conn.adapter :typhoeus
      end
    end
    private_class_method :new_connection

    def self.handle_request_error(res)
      return if res.status == 200 || res.success?

      raise ApiError.new("There was an error fetching the models from the Azure Models Service (HTTP #{res.status})")
    end
    private_class_method :handle_request_error

    sig do
      params(
        res: ::Faraday::Response,
        service_name: String,
      ).returns(T.untyped)
    end
    def self.parse_response_json(res:, service_name:)
      JSON.parse(res.body)
    rescue JSON::ParserError
      msg = "There was an error parsing the response from the #{service_name} service"
      raise ApiError.new(msg)
    end
    private_class_method :parse_response_json

    sig { params(has_free_playground: T::Boolean).returns(T::Hash[T.untyped, T.untyped]) }
    def self.request_payload(has_free_playground)
      payload = {
        "pageSize": 100,
        "filters": [
          { "field": "labels", "values": ["latest"], "operator": "eq" },
        ],
        "order": [
          { "field": "displayName", "direction": "Asc" }
        ]
      }

      if has_free_playground
        payload[:filters].push({ "field": "freePlayground", "values": ["true"], "operator": "eq" })
      end

      payload
    end
  end
end
