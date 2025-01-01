# typed: true
# frozen_string_literal: true

module AzureModels
  module Client
    extend T::Sig
    include AzureModels::Parseable

    MODELS_ENDPOINT = "/models"
    MODELS_ENDPOINT_V2 = "/asset-gallery/v1.0/models"

    class ApiError < StandardError; end

    sig { returns(T::Array[Marketplace::Types::AzureModels::Model]) }
    def self.fetch_models
      raw_res = new_connection(GitHub.azure_ai_studio_url)
                  .get(MODELS_ENDPOINT)
      self.handle_request_error(raw_res)

      to_azure_models(JSON.parse(raw_res.body))
    end

    sig { returns(T::Array[Marketplace::Types::AzureModels::Model]) }
    def self.fetch_models_v2
      raw_res = new_connection(GitHub.azure_ai_studio_url_v2)
                  .post(MODELS_ENDPOINT_V2, request_payload)
      self.handle_request_error(raw_res)

      to_azure_models_v2(JSON.parse(raw_res.body))
    end

    sig { params(registry: String, model_name: String).returns(T.nilable(Marketplace::Types::AzureModels::RenderableModel)) }
    def self.fetch_model(registry:, model_name:)
      model = fetch_model_details(registry:, model: model_name)
      schema = fetch_model_schema(registry:, model: model_name)

      unless model.present? && schema.present?
        raise ApiError.new("There was an error fetching either the model or schema for #{model_name}")
      end

      {
        model: model,
        schema: schema
      }
    end

    sig { params(registry: String, model: String).returns(T.nilable(Marketplace::Types::AzureModels::Model)) }
    def self.fetch_model_details(registry:, model:)
      raw_res = new_connection(GitHub.azure_ai_studio_url)
                  .get("/model/#{registry}/#{model}")
      self.handle_request_error(raw_res)

      to_azure_model(JSON.parse(raw_res.body), registry)
    end

    sig { params(registry: String, model: String).returns(T.nilable(Marketplace::Types::AzureModels::ModelSchema)) }
    def self.fetch_model_schema(registry:, model:)
      raw_res = new_connection(GitHub.azure_ai_model_schema_url)
                  .get("/widgets/en/Serverless/#{registry}/#{model.downcase}.json")
      self.handle_request_error(raw_res)

      to_model_schema(JSON.parse(raw_res.body))
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
