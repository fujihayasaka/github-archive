# typed: strict
# frozen_string_literal: true

module GitHubModels
  class Types
    # Keep in sync with `ModelListing` in ui/packages/marketplace-common/types.ts.
    ModelListing = T.type_alias do
      {
        id: String,
        registry: String,
        name: String,
        friendly_name: String,
        task: String,
        publisher: String,
        summary: String,
        tags: T::Array[String],
        max_output_tokens: Integer,
        max_input_tokens: Integer,
        logo_url: T.nilable(String),
        dark_mode_icon: T.nilable(String),
        light_mode_icon: T.nilable(String),
        type: T.nilable(String),
        model_url: T.nilable(String)
      }
    end

    RenderableModel = T.type_alias do
      {
        model: Model,
        schema: ModelSchema
      }
    end

    MarkdownTocItem = T.type_alias do
      {
        level: Integer,
        text: String,
        anchor: String
      }
    end

    # Representation of a model for use in the models catalog. A subset of data from `Model`, used to display the
    # model in a list of many models at once.
    # Keep in sync with `FeaturedModel` in ui/packages/marketplace-common/types.ts.
    FeaturedModel = T.type_alias do
      {
        id: String,
        registry: String,
        name: String,
        friendly_name: String,
        publisher: String,
        summary: String,
        logo_url: T.nilable(String),
        light_mode_icon: T.nilable(String),
        dark_mode_icon: T.nilable(String),
      }
    end

    sig { params(model: Model).returns(FeaturedModel) }
    def self.featured_model_for(model)
      {
        id: model[:id],
        registry: model[:registry],
        name: model[:name],
        friendly_name: model[:friendly_name],
        publisher: model[:publisher],
        summary: model[:summary],
        logo_url: model[:logo_url],
        light_mode_icon: model[:light_mode_icon],
        dark_mode_icon: model[:dark_mode_icon],
      }
    end

    # Keep in sync with `Model` in ui/packages/marketplace-common/types.ts
    Model = T.type_alias do
      {
        id: String,
        registry: String,
        name: String,
        original_name: String,
        friendly_name: String,
        task: String,
        publisher: String,
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
      }
    end

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

    Preset = T.type_alias do
      {
        name: String,
        parameters: PresetParameters,
        private: T::Boolean,
        urlIdentifier: String,
      }
    end

    PresetParameters = T.type_alias do
      {
        system_prompt: String,
        chat_prompt: String,
      }
    end

    ModelDetails = T.type_alias do
      {
        catalogData: Model,
        modelInputSchema: T.nilable(ModelSchema),
        gettingStarted: T::Hash[Symbol, T.untyped],
      }
    end

    # Keep in sync with `OrganizationAccessPolicy` in ui/packages/github-models-org-settings/types.ts
    OrganizationAccessPolicy = T.type_alias do
      {
        isAllowlist: T::Boolean,
        isModelsEnabled: T::Boolean,
        allowedModelKeys: T::Array[String],
      }
    end

    # Keep in sync with `Publisher` in ui/packages/github-models-org-settings/types.ts
    Publisher = T.type_alias do
      {
        id: Integer,
        name: String,
        logoUrl: T.nilable(String),
        darkModeIcon: T.nilable(String),
        lightModeIcon: T.nilable(String),
        totalModels: Integer
      }
    end

    # Keep in sync with `Model` in ui/packages/github-models-org-settings/types.ts
    OrganizationAccessPolicyShowModel = T.type_alias do
      {
        key: String,
        registry: String,
        name: String,
        friendlyName: String,
        publisherId: Integer,
      }
    end

    # Keep in sync with `AccessPolicyShowPayload` in ui/packages/github-models-org-settings/types.ts
    OrganizationAccessPolicyShowPayload = T.type_alias do
      {
        orgDisplayLogin: String,
        policy: OrganizationAccessPolicy,
        publishers: T::Array[Publisher],
        models: T::Array[OrganizationAccessPolicyShowModel]
      }
    end

    ShowPayload = T.type_alias do
      {
        model: GitHubModels::Types::Model,
        modelEvaluation: String,
        modelInputSchema: T.nilable(GitHubModels::Types::ModelSchema),
        modelTransparencyContent: String,
        modelReadme: String,
        readmeToc: T::Array[GitHubModels::Types::MarkdownTocItem],
        playgroundUrl: String,
        gettingStarted: T::Hash[Symbol, T.untyped],
        miniplaygroundIcebreaker: T.nilable(String),
        modelLicense: String,
        canProvideAdditionalFeedback: T::Boolean,
        isLoggedIn: T::Boolean,
        restrictedModels: T::Array[String],
        comparedModelDetails: T.nilable(GitHubModels::Types::ModelDetails),
        appliedPreset: T.nilable(GitHubModels::Types::Preset),
        promptExtractionCodeSnippet: T.nilable(String),
        improvedPromptModel: T.nilable(GitHubModels::Types::Model),
        promptExtractionModel: T.nilable(GitHubModels::Types::Model),
        promptFeedbackBannerDismissed: T.nilable(T::Boolean),
        playgroundFeedbackPopoverDismissed: T.nilable(T::Boolean),
      }
    end

    module Static
      GPT4o = T.let(
        {
          id: "gpt-4o:1",
          registry: "azure-openai",
          name: "gpt-4o",
          original_name: "gpt-4o",
          friendly_name: "gpt-4o",
          task: "chat-completion",
          publisher: "OpenAI",
          license: "",
          description: "## Model Family: GPT-4\n" + "\n" + "GPT-4o is OpenAI's most advanced model to date. This multimodal model handles both text and image inputs while generating text outputs. Matching the intelligence of GPT-4 Turbo, it is remarkably more efficient, delivering text at twice the speed and at half the cost. Additionally, GPT-4o exhibits the highest vision performance and excels in non-English languages compared to previous OpenAI models.\n" + "\n" + "> Note: You can deploy GPT-4o in the following US regions only at this time: eastus, eastus2, northcentralus, southcentralus, westus, westus3.\n",
          summary: "",
          notes: "",
          model_version: "2024-05-13",
          popularity: 54.98,
          tags: [],
          rate_limit_tier: "high",
          supported_languages: ["English"],
          max_output_tokens: 4096,
          max_input_tokens: 131072,
          training_data_date: "2023-10-01T00:00:00+00:00",
          logo_url: "",
          dark_mode_icon: "",
          light_mode_icon: "",
          evaluation: "",
          license_description: "",
          supported_input_modalities: %w[text image audio],
          supported_output_modalities: ["text"],
        }, Model)

      GPT4 = T.let(
        {
          id: "gpt-4:5",
          registry: "azure-openai",
          name: "gpt-4",
          original_name: "gpt-4",
          friendly_name: "gpt-4",
          task: "chat-completion",
          publisher: "OpenAI",
          license: "",
          description: "This description is artificially short",
          summary: "What you need to know",
          notes: "",
          model_version: "5",
          popularity: nil,
          tags: [],
          rate_limit_tier: "high",
          supported_languages: ["English"],
          max_output_tokens: 4096,
          max_input_tokens: 131072,
          training_data_date: "2023-10-01T00:00:00+00:00",
          logo_url: "",
          dark_mode_icon: "",
          light_mode_icon: "",
          evaluation: "",
          license_description: "",
          supported_input_modalities: %w[text image audio],
          supported_output_modalities: ["text"],
        }, Model)

      GPT4_SCHEMA = T.let(
        {
          examples: [
            {
              "chatHistory": [
                { "role": "user", "content": "I am going to Paris, what should I see?" },
                { "role": "assistant", "content": "Paris, the capital of France, is known for its stunning architecture, art museums, historical landmarks, and romantic atmosphere. Here are some of the top attractions to see in Paris:\n\n1. The Eiffel Tower: The iconic Eiffel Tower is one of the most recognizable landmarks in the world and offers breathtaking views of the city.\n2. The Louvre Museum: The Louvre is one of the world's largest and most famous museums, housing an impressive collection of art and artifacts, including the Mona Lisa.\n3. Notre-Dame Cathedral: This beautiful cathedral is one of the most famous landmarks in Paris and is known for its Gothic architecture and stunning stained glass windows.\n\nThese are just a few of the many attractions that Paris has to offer. With so much to see and do, it's no wonder that Paris is one of the most popular tourist destinations in the world." },
                { "role": "user", "content": "What is so great about #1?" }
              ]
            }
          ],
          sampleInputs: [
            { "messages": [{ "role": "user", "content": "What is the history of the Great Wall of China?" }] },
            { "messages": [{ "role": "user", "content": "Can you explain the concept of time dilation in physics?" }] },
            { "messages": [{ "role": "user", "content": "What are some popular tourist attractions in Paris?" }] },
            { "messages": [{ "role": "user", "content": "What are some of the most famous works of Shakespeare?" }] },
            { "messages": [{ "role": "user", "content": "Can you explain the basics of machine learning?" }] },
            { "messages": [{ "role": "user", "content": "What are some common features of Gothic architecture?" }] },
          ],
          inputs: [{ "key": "chatHistory", "friendlyName": "Chat History", "type": "array", "payloadPath": "messages", "required": true }],
          outputs: [{ "key": "choices", "friendlyName": "Result", "type": "array", "payloadPath": "choices" }],
          fixedParameters: [],
          capabilities: { "bringYourOwnData": true, "systemPrompt": true },
          type: "Chat",
          version: "0.1",
          behavior: "OAILikeChat",
          parameters: [
            { "key": "max_tokens", "type": "integer", "payloadPath": "max_tokens", "default": 256, "min": 1, "max": 32000, "required": true },
            { "key": "temperature", "type": "number", "payloadPath": "temperature", "default": 1, "max": 1, "min": 0, "required": false },
            { "key": "top_p", "type": "number", "payloadPath": "top_p", "default": 1, "max": 1, "min": 0, "required": false },
            { "key": "stop", "type": "array", "payloadPath": "stop", "default": [], "required": false }
          ]
        }, ModelSchema
      )

      GPT4o_SCHEMA = T.let(
        {
          examples: [
            {
              "chatHistory": [
                { "role": "user", "content": "I am going to Paris, what should I see?" },
                { "role": "assistant", "content": "Paris, the capital of France, is known for its stunning architecture, art museums, historical landmarks, and romantic atmosphere. Here are some of the top attractions to see in Paris:\n\n1. The Eiffel Tower: The iconic Eiffel Tower is one of the most recognizable landmarks in the world and offers breathtaking views of the city.\n2. The Louvre Museum: The Louvre is one of the world's largest and most famous museums, housing an impressive collection of art and artifacts, including the Mona Lisa.\n3. Notre-Dame Cathedral: This beautiful cathedral is one of the most famous landmarks in Paris and is known for its Gothic architecture and stunning stained glass windows.\n\nThese are just a few of the many attractions that Paris has to offer. With so much to see and do, it's no wonder that Paris is one of the most popular tourist destinations in the world." },
                { "role": "user", "content": "What is so great about #1?" }
              ]
            }
          ],
          sampleInputs: [
            { "messages": [{ "role": "user", "content": "What is the history of the Great Wall of China?" }] },
            { "messages": [{ "role": "user", "content": "Can you explain the concept of time dilation in physics?" }] },
            { "messages": [{ "role": "user", "content": "What are some popular tourist attractions in Paris?" }] },
            { "messages": [{ "role": "user", "content": "What are some of the most famous works of Shakespeare?" }] },
            { "messages": [{ "role": "user", "content": "Can you explain the basics of machine learning?" }] },
            { "messages": [{ "role": "user", "content": "What are some common features of Gothic architecture?" }] },
          ],
          inputs: [{ "key": "chatHistory", "friendlyName": "Chat History", "type": "array", "payloadPath": "messages", "required": true }],
          outputs: [{ "key": "choices", "friendlyName": "Result", "type": "array", "payloadPath": "choices" }],
          fixedParameters: [],
          capabilities: { "bringYourOwnData": true, "systemPrompt": true },
          type: "Chat",
          version: "0.1",
          behavior: "OAILikeChat",
          parameters: [
            { "key": "max_tokens", "type": "integer", "payloadPath": "max_tokens", "default": 256, "min": 1, "max": 32000, "required": true },
            { "key": "temperature", "type": "number", "payloadPath": "temperature", "default": 1, "max": 1, "min": 0, "required": false },
            { "key": "top_p", "type": "number", "payloadPath": "top_p", "default": 1, "max": 1, "min": 0, "required": false },
            { "key": "stop", "type": "array", "payloadPath": "stop", "default": [], "required": false }
          ]
        }, ModelSchema
      )
    end
  end
end
