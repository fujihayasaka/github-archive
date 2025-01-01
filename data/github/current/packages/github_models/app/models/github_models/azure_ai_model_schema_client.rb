# typed: true
# frozen_string_literal: true

module GitHubModels
  class AzureAiModelSchemaClient < ApiClient
    # This is a temporary mapping to allow us to launch models that don't have entries in the schema yet.
    # Keys and values must be in the format registry/model_name.downcase
    SCHEMA_MAPPING = {
      "azureml/phi-4-multimodal-instruct" => "azureml/phi-3.5-vision-instruct"
    }.freeze
    SERVICE_NAME = "Azure AI Model Schema"

    def initialize
      super(api_url: GitHub.azure_ai_model_schema_url, service_name: SERVICE_NAME)
    end

    sig { params(registry: String, model: String).returns(GitHubModels::Types::ModelSchema) }
    def fetch_model_schema(registry:, model:)
      # We need to launch some models that don't have entries in the schema yet. This allows us to
      # substitute a schema from a model that does exist
      url_registry, url_model = if SCHEMA_MAPPING["#{registry}/#{model.downcase}"].present?
        SCHEMA_MAPPING["#{registry}/#{model.downcase}"].split("/")
      else
        [registry, model.downcase]
      end

      raw_res = connection.get("/widgets/en/Serverless/#{url_registry}/#{url_model}.json")
      handle_request_error(raw_res, action: "fetching model schema")

      schema_details = parse_response_json(res: raw_res)
      unless schema_details.present?
        raise GitHubModels::ApiClient::ApiError.new("There was an error fetching the schema for #{model}")
      end

      to_model_schema(schema_details)
    end

    private

    # This method is used to parse the response from the model schema endpoint.
    sig { params(schema: T::Array[T::Hash[T.untyped, T.untyped]]).returns(GitHubModels::Types::ModelSchema) }
    def to_model_schema(schema)
      schema = T.must_because(schema[0]) { "The response needs to have one top-level object in the array" }
      schema = schema["config"]

      {
        examples: schema["examples"],
        sampleInputs: schema["sampleInputs"]&.sample(3) || [], # get 3 random sample inputs
        inputs: schema["inputs"],
        outputs: schema["outputs"],
        fixedParameters: schema["fixedParameters"],
        capabilities: schema["capabilities"],
        type: schema["type"],
        version: schema["version"],
        behavior: schema["behavior"],
        parameters: schema["parameters"]
      }
    end
  end
end
