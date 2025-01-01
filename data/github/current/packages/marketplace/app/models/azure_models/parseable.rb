# typed: true
# frozen_string_literal: true

module AzureModels
  module Parseable
    extend ActiveSupport::Concern

    class_methods do
      extend T::Sig

      # This method is used to parse the response from the models list endpoint.
      sig do
        params(json: T::Array[T::Hash[String, T.untyped]])
          .returns(T::Array[Marketplace::Types::AzureModels::Model])
      end
      def to_azure_models(json)
        json.map do |model|
          # We could just return the raw response from the models list endpoint here,
          # but I'd like to prevent against the API changing from underneath or feet
          # and returning random data.
          {
            id: model["id"],
            registry: model["model_registry"],
            name: model["name"].gsub(".", "-"),
            original_name: model["name"], # used to fetch details
            friendly_name: model["friendly_name"],
            task: model["task"],
            publisher: model["publisher"],
            license: model["license"],
            description: model["description"],
            samples: model["samples"],
            summary: model["summary"],
            model_family: model["model_family"],
            model_version: model["model_version"],
            notes: "", # Currently notes are only included in the model details response
            tags: model["tags"],
            rate_limit_tier: nil,
            supported_languages: [],
            max_output_tokens: nil,
            max_input_tokens: 0,
            training_data_date: "",
            logo_url:  "/images/modules/marketplace/models/families/#{model["model_family"].downcase}.svg",
            evaluation: "", # Currently evaluation is only included in the model details response
            license_description: "", # Currently license_description is only included in the model details response
          }
        end
      end

      # This method is used to parse the response from the models list v2 endpoint.
      sig do
        params(json: T::Hash[String, T.untyped])
          .returns(T::Array[Marketplace::Types::AzureModels::Model])
      end
      def to_azure_models_v2(json)
        # In Details v2, the models are nested under the "summaries" key
        json = json["summaries"]

        json.map do |model|
          # We could just return the raw response from the models list endpoint here,
          # but I'd like to prevent against the API changing from underneath or feet
          # and returning random data.
          {
            id: model["assetId"],
            registry: model["registryName"],
            name: model["name"].gsub(".", "-"),
            original_name: model["name"], # used to fetch details
            friendly_name: model["displayName"],
            task: model["inferenceTasks"]&.first, # in v2, this is now a list as opposed to a string in v1
            publisher: model["publisher"],
            license: model["license"], # TODO: Ask Azure about this. Where it used to be "custom" in v1, it's now null in v2
            description: "", # in Details v2 response
            samples: nil, # TODO: Remove - no longer being used. Samples are now in the schema response.
            summary: model["summary"],
            model_family: model["publisher"], # model_family no longer exists in v2 so we're recommended to use publisher instead
            model_version: model["version"]&.to_i, # Comes in as a string but we need it as an integer
            notes: "", # in Details v2 response
            tags: [], # in Details v2 response as keywords
            rate_limit_tier: nil,
            supported_languages: [],
            max_output_tokens: nil,
            max_input_tokens: 0,
            training_data_date: "",
            logo_url: "/images/modules/marketplace/models/families/#{model["publisher"].downcase}.svg",
            evaluation: "", # in Details v2 response
            license_description: "", # in Details v2 response
          }
        end
      end

      # This method is used to parse the response from the model details endpoint.
      sig do
        params(model_json: T::Hash[String, T.untyped], requested_registry: String)
          .returns(Marketplace::Types::AzureModels::Model)
      end
      def to_azure_model(model_json, requested_registry)
        # TODO: Remove the fallbacks here and error out once API spec has been finalized
        {
          id: model_json["id"],
          registry: requested_registry,
          name: model_json["name"].gsub(".", "-"), # used for urls/keys
          original_name: model_json["name"], # used to fetch details
          friendly_name: model_json["friendly_name"],
          task: model_json["task"],
          publisher: model_json["publisher"],
          license: model_json["license"] || "", # temporary fallback until the API returns the correct value
          description: model_json["description"],
          samples: get_random_samples(model_json["samples"]),
          summary: model_json["summary"],
          model_family: model_json["model_family"],
          model_version: model_json["model_version"],
          notes: model_json["notes"],
          tags: model_json["tags"],
          rate_limit_tier: model_json.dig("properties", "limits", "rate", "model_class"),
          supported_languages: model_json.dig("properties", "limits", "languages") || [],
          max_output_tokens: model_json.dig("properties", "limits", "outputs", "tokens"),
          max_input_tokens: model_json.dig("properties", "limits", "inputs", "tokens") || 0,
          training_data_date: model_json.dig("properties", "training_data"),
          logo_url: "/images/modules/marketplace/models/families/#{model_json["model_family"].downcase}.svg",
          evaluation: model_json["evaluation"],
          license_description: model_json["license_description"],
        }
      end

      # This method is used to parse the response from the model schema endpoint.
      sig { params(schema: T::Array[T::Hash[T.untyped, T.untyped]]).returns(Marketplace::Types::AzureModels::ModelSchema) }
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

      sig { params(samples: T::Hash[String, T::Array[T::Hash[String, T.untyped]]]).returns(T::Hash[String, T.untyped]) }
      def get_random_samples(samples)
        # Get 3 random samples from the list of samples
        return {} if samples.nil?

        random_samples = samples["inputs"]&.sample(3)
        {
          code: samples["code"],
          inputs: random_samples
        }
      end
    end
  end
end
