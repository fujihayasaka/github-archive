# typed: true
# frozen_string_literal: true

module AzureModels
  module Client
    include AzureModels::Parseable

    MODELS_ENDPOINT = "/asset-gallery/v1.0/models"
    PUBLISHERS_ENDPOINT = "/intellectualPropertyPublisher/v1.0/publisherDetails"
    PUBLISHERS_CALL_ERROR_MESSAGE = "Skipping over publisher data in catalog sync"

    class ApiError < StandardError; end

    sig { returns(T::Array[GitHubModels::Types::Model]) }
    def self.fetch_models
      model_res = new_connection(GitHub.azure_ai_studio_url)
        .post(MODELS_ENDPOINT, request_payload)
      self.handle_request_error(model_res)

      publisher_res = new_connection(GitHub.azure_ai_publishers_url)
        .get(PUBLISHERS_ENDPOINT)
      self.handle_request_error(publisher_res)

      models = parse_response_json(res: model_res, service_name: "Azure Models")

      publishers = begin
        parse_response_json(res: publisher_res, service_name: "Publishers")
      rescue ApiError => e
        GitHub.dogstats.increment("github_models.catalog_sync_failure", tags: ["publisher_data:true"])
        GitHub::Chatterbox.client.say!("#github-models-ops", "Couldn't sync publisher icon information, error: #{e.message}")
        GitHub.logger.error(PUBLISHERS_CALL_ERROR_MESSAGE, e.message)
        {}
      end

      to_azure_models(models:, publishers:)
    end

    sig { params(registry: String, model_name: String, version: String).returns(T.nilable(GitHubModels::Types::RenderableModel)) }
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

    sig { params(registry: String, model: String, version: String).returns(T.nilable(GitHubModels::Types::Model)) }
    def self.fetch_model_details(registry:, model:, version:)
      raw_res = new_connection(GitHub.azure_ai_studio_url)
        .get("/asset-gallery/v1.0/#{registry}/models/#{model}/version/#{version}")
      self.handle_request_error(raw_res)
      model_details = parse_response_json(res: raw_res, service_name: "Model Details")

      to_azure_model(model_details, registry)
    end

    sig { params(registry: String, model: String).returns(T.nilable(GitHubModels::Types::ModelSchema)) }
    def self.fetch_model_schema(registry:, model:)
      raw_res = new_connection(GitHub.azure_ai_model_schema_url)
        .get("/widgets/en/Serverless/#{registry}/#{model.downcase}.json")
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

        conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: GitHub::Config::Neutron::SERVICE_NAME
        conn.adapter :typhoeus
      end
    end
    private_class_method :new_connection

    def self.handle_request_error(res)
      return if res.status == 200 || res.success?

      raise ApiError.new("There was an error fetching the models from the Azure Models Service")
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

    def self.request_payload
      payload = {
        "filters": [
          { "field": "freePlayground", "values": ["true"], "operator": "eq" },
          { "field": "labels", "values": ["latest"], "operator": "eq" },
        ],
        "order": [
          { "field": "displayName", "direction": "Asc" }
        ]
      }

      payload.to_json
    end
  end
end
