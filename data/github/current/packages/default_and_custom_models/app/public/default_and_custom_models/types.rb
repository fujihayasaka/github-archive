# typed: strict
# frozen_string_literal: true

module DefaultAndCustomModels
  class Types
    # Keep in sync with `Model` in ui/packages/marketplace-common/types.ts
    # Consists of the data necessary for the frontend to render a model in the playground, either in a repository
    # or in Marketplace.
    Model = T.type_alias do
      {
        id: String,
        registry: String,
        name: String,
        original_name: String,
        friendly_name: String,
        task: String,
        publisher: String,
        publisherDisplayName: T.nilable(String),
        license: String,
        description: String,
        summary: String,
        model_version: String,
        notes: String,
        popularity: T.nilable(Float),
        tags: T::Array[String],
        rate_limit_tier: T.nilable(String),
        supported_languages: T::Array[String],
        max_output_tokens: T.nilable(Integer),
        max_input_tokens: T.nilable(Integer),
        training_data_date: T.nilable(String),
        logo_url: T.nilable(String),
        dark_mode_icon: T.nilable(String),
        light_mode_icon: T.nilable(String),
        evaluation: T.nilable(String),
        license_description: T.nilable(String),
        supported_input_modalities: T::Array[String],
        supported_output_modalities: T::Array[String],
        publisherSlug: String,
        capabilities: {
          jsonSchemaStructuredOutput: T::Boolean,
          tokenCounting: T::Boolean,
          streaming: T::Boolean,
          streamingOptions: T::Boolean,
          structuredOutput: T::Boolean,
        },
        isRestricted: T::Boolean,
        isBillable: T.nilable(T::Boolean),
        isCustom: T.nilable(T::Boolean),
      }
    end

    # Used by the frontend to render a model in the playground, either in a repository or in Marketplace.
    # Model schema(s) available for a given model at:
    # https://modelcatalogcache-fac7dncjgsgqbchj.b02.azurefd.net/widgets/en/Serverless/#{registry}/#{model.downcase}.json
    ModelSchema = T.type_alias do
      {
        examples: T::Array[T::Hash[T.untyped, T.untyped]],
        sampleInputs: T::Array[T::Hash[T.untyped, T.untyped]],
        inputs: T::Array[T::Hash[T.untyped, T.untyped]],
        outputs: T::Array[T::Hash[T.untyped, T.untyped]],
        fixedParameters: T::Array[T::Hash[T.untyped, T.untyped]],
        capabilities: T.nilable(T::Hash[T.untyped, T.untyped]),
        type: String,
        version: String,
        behavior: T.nilable(String),
        parameters: T::Array[T::Hash[T.untyped, T.untyped]],
      }
    end

    # Keep in sync with `RepoModel` in ui/packages/github-models-repo/types.ts
    # Consists of the data necessary for the frontend to render a model in a repository, either in the playground
    # or in the prompt editor.
    RepoModel = T.type_alias do
      {
        dark_mode_icon: T.nilable(String),
        friendly_name: String,
        id: String,
        light_mode_icon: T.nilable(String),
        logo_url: T.nilable(String),
        name: String,
        original_name: String,
        publisher: String,
        publisherDisplayName: T.nilable(String),
        publisherSlug: String,
        registry: String,
        summary: String,
        task: String,
        capabilities: {
          jsonSchemaStructuredOutput: T::Boolean,
          streaming: T::Boolean,
          streamingOptions: T::Boolean,
          structuredOutput: T::Boolean,
          systemPrompt: T::Boolean,
          tokenCounting: T::Boolean,
          modelInputSchemaParameters: T::Array[T::Hash[T.untyped, T.untyped]],
        },
        isRestricted: T::Boolean,
        isCustom: T.nilable(T::Boolean),
      }
    end
  end
end
