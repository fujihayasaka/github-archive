# typed: true
# frozen_string_literal: true

module AzureModels
  module Parseable
    extend ActiveSupport::Concern

    class_methods do

      # This method is used to parse the response from the Azure Catalog List endpoint
      sig do
        params(models: T::Hash[String, T.untyped], publishers: T::Hash[String, T.untyped])
          .returns(T::Array[GitHubModels::Types::Model])
      end
      def to_azure_models(models:, publishers:)
        # Models are nested under the "summaries" key in the JSON response
        models = models["summaries"]
        publishers = publishers.fetch("value", []).each_with_object({}) do |publisher, acc|
          acc[publisher["publisherName"]] = { "icon_dark" => publisher["iconDark"], "icon_light" => publisher["iconLight"] }
          acc
        end

        models.map do |model|
          publisher_data = publishers.fetch(model["publisher"], {})

          # We could just return the raw response from the models list endpoint here,
          # but I'd like to prevent against the API changing from underneath or feet
          # and returning random data.
          {
            id: model["assetId"],
            registry: model["registryName"], # Used to fetch details
            name: model["name"].gsub(".", "-"),
            original_name: model["name"], # Used to fetch details
            friendly_name: model["displayName"],
            task: model["inferenceTasks"]&.first, # This is a list but used to be a String in V1/Nexus
            publisher: model["publisher"],
            license: model["license"],
            description: "", # In Details response
            summary: model["summary"],
            model_family: model["publisher"],
            model_version: model["version"],
            notes: "", # In Details response
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
            static_model: false,
          }
        end
      end

      # This method is used to parse the response from the model details endpoint.
      sig do
        params(model_json: T::Hash[String, T.untyped], requested_registry: String)
          .returns(GitHubModels::Types::Model)
      end
      def to_azure_model(model_json, requested_registry)
        # TODO: Remove the fallbacks here and error out once API spec has been finalized
        {
          id: model_json["assetId"],
          registry: requested_registry,
          name: model_json["name"].gsub(".", "-"), # Used for URLs/keys
          original_name: model_json["name"],
          friendly_name: model_json["displayName"],
          task: model_json["inferenceTasks"]&.first, # This is a list but used to be a String in V1/Nexus
          publisher: model_json["publisher"],
          license: model_json["license"] || "",
          description: model_json["description"],
          summary: model_json["summary"],
          model_family: model_json["publisher"],
          model_version: model_json["version"],
          notes: model_json["notes"],
          tags: model_json["keywords"]&.map { |k| k.downcase },
          rate_limit_tier: model_json.dig("playgroundLimits", "rateLimitTier"),
          supported_languages: model_json.dig("modelLimits", "supportedLanguages") || [],
          max_output_tokens: model_json.dig("modelLimits", "textLimits", "maxOutputTokens"),
          max_input_tokens: model_json.dig("modelLimits", "textLimits", "inputContextWindow") || 0,
          training_data_date: format_training_date(model_json["trainingDataDate"]),
          logo_url: "/images/modules/marketplace/models/families/#{model_json["publisher"].downcase}.svg",
          dark_mode_icon: model_json["icon_dark"],
          light_mode_icon: model_json["icon_light"],
          evaluation: model_json["evaluation"],
          license_description: model_json["licenseDescription"],
          static_model: false,
          supported_input_modalities: model_json.dig("modelLimits", "supportedInputModalities") || [],
          supported_output_modalities: model_json.dig("modelLimits", "supportedOutputModalities") || [],
        }
      end

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

      # Formats the training date from 2023-10-01T00:00:00+00:00 to Oct 2023
      sig { params(datetime_string: T.nilable(String)).returns(T.nilable(String)) }
      def format_training_date(datetime_string)
        return if datetime_string.nil?

        DateTime.parse(datetime_string).strftime("%b %Y")
      end
    end
  end
end
