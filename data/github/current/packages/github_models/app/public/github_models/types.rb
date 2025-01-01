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
        publisherDisplayName: T.nilable(String),
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
        model: DefaultAndCustomModels::Types::Model,
        schema: DefaultAndCustomModels::Types::ModelSchema
      }
    end

    MarkdownTocItem = T.type_alias do
      {
        level: Integer,
        text: String,
        anchor: String
      }
    end

    # Representation of a model for use in the models catalog. A subset of data from
    # `DefaultAndCustomModels::Types::Model`, used to display the model in a list of many models at once.
    # Keep in sync with `FeaturedModel` in ui/packages/marketplace-common/types.ts.
    FeaturedModel = T.type_alias do
      {
        id: String,
        registry: String,
        name: String,
        friendly_name: String,
        publisher: String,
        publisherDisplayName: T.nilable(String),
        summary: String,
        logo_url: T.nilable(String),
        light_mode_icon: T.nilable(String),
        dark_mode_icon: T.nilable(String),
      }
    end

    sig { params(model: DefaultAndCustomModels::Types::Model).returns(FeaturedModel) }
    def self.featured_model_for(model)
      publisher_name = model[:publisher]
      publisher_display_name = GitHubModels::Publisher.display_name_for(publisher_name)
      {
        id: model[:id],
        registry: model[:registry],
        name: model[:name],
        friendly_name: model[:friendly_name],
        publisher: publisher_name,
        publisherDisplayName: publisher_display_name == publisher_name ? nil : publisher_display_name,
        summary: model[:summary],
        logo_url: model[:logo_url],
        light_mode_icon: model[:light_mode_icon],
        dark_mode_icon: model[:dark_mode_icon],
      }
    end

    MultiplierPayload = T.type_alias do
      {
        model: T.nilable(String),
        input: String,
        cached_input: T.nilable(String),
        output: String,
      }
    end

    ModelPricing = T.type_alias do
      {
        input: String,
        cachedInput: T.nilable(String),
        output: String,
      }
    end

    DocUrls = T.type_alias do
      {
        rateLimit: String,
        usingActions: String,
        restApi: String,
        aboutGitHubModels: String,
        managingPat: String,
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
        catalogData: DefaultAndCustomModels::Types::Model,
        modelInputSchema: T.nilable(DefaultAndCustomModels::Types::ModelSchema),
        gettingStarted: T::Hash[Symbol, T.untyped],
        pricing: T.nilable(ModelPricing),
      }
    end

    # Keep in sync with `OrganizationAccessPolicy` in ui/packages/github-models-org-settings/types.ts
    OrganizationAccessPolicy = T.type_alias do
      {
        isAllowlist: T::Boolean,
        isModelsEnabled: T::Boolean,
        isAccessConfigurable: T::Boolean,
        allowedModelKeys: T::Array[String],
        allowedCustomModelIds: T::Array[Integer],
        isMarketplaceEnabled: T::Boolean,
      }
    end

    # Keep in sync with `Publisher` in ui/packages/github-models-org-settings/types.ts
    Publisher = T.type_alias do
      {
        id: Integer,
        name: String,
        displayName: T.nilable(String),
        logoUrl: T.nilable(String),
        darkModeIcon: T.nilable(String),
        lightModeIcon: T.nilable(String),
        totalModels: Integer
      }
    end

    # Keep in sync with `ModelsSearchFiltersPayload` in ui/packages/marketplace-common/types.ts
    SearchFiltersPayload = T.type_alias do
      { categories: T::Array[String], publishers: T::Array[Publisher] }
    end

    # Keep in sync with `DefaultModel` in ui/packages/github-models-org-settings/types.ts
    OrganizationAccessPolicyShowModel = T.type_alias do
      {
        key: String,
        registry: String,
        name: String,
        friendlyName: String,
        publisherId: Integer,
      }
    end

    # Keep in sync with `RepositoryAccessPolicy` in ui/packages/github-models-org-settings/types.ts
    RepositoryAccessPolicy = T.type_alias do
      {
        isRepoModelsEnabled: T::Boolean,
      }
    end

    # Keep in sync with `RepositoryAccessPolicyShowPayload` in ui/packages/github-models-repo-settings/types.ts
    RepositoryAccessPolicyShowPayload = T.type_alias do
      {
        ownerDisplayLogin: String,
        repositoryName: String,
        isAccessConfigurable: T::Boolean,
        repositoryOwnerType: String,
        repositoryAccessPolicy: RepositoryAccessPolicy,
      }
    end

    ShowPayload = T.type_alias do
      {
        model: T.any(DefaultAndCustomModels::Types::Model, DefaultAndCustomModels::Types::RepoModel),
        modelEvaluation: String,
        modelInputSchema: T.nilable(DefaultAndCustomModels::Types::ModelSchema),
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
        improvedPromptModel: T.nilable(DefaultAndCustomModels::Types::Model),
        promptExtractionModel: T.nilable(DefaultAndCustomModels::Types::Model),
        promptFeedbackBannerDismissed: T.nilable(T::Boolean),
        isBillingEnabled: T.nilable(T::Boolean),
        inRepoContext: T.nilable(T::Boolean),
        showPlaygroundPaidUsageBanner: T.nilable(T::Boolean),
        pricing: T.nilable(GitHubModels::Types::ModelPricing),
        docUrls: T.nilable(T::Hash[String, String])
      }
    end

    RepositoryPrompt = T.type_alias do
      {
        name: T.nilable(String),
        description: T.nilable(String),
        path: String,
        model: T.nilable(String)
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
          publisherDisplayName: "Azure OpenAI Service",
          license: "",
          description: "## Model Family: GPT-4\n\nGPT-4o is OpenAI's most advanced model to date. This multimodal model handles both text and image inputs while generating text outputs. Matching the intelligence of GPT-4 Turbo, it is remarkably more efficient, delivering text at twice the speed and at half the cost. Additionally, GPT-4o exhibits the highest vision performance and excels in non-English languages compared to previous OpenAI models.\n\n> Note: You can deploy GPT-4o in the following US regions only at this time: eastus, eastus2, northcentralus, southcentralus, westus, westus3.\n",
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
          publisherSlug: "openai",
          capabilities: {
            jsonSchemaStructuredOutput: true,
            tokenCounting: true,
            streaming: true,
            streamingOptions: true,
            structuredOutput: true,
          },
          isRestricted: false,
          isBillable: false,
          isCustom: false,
        }, DefaultAndCustomModels::Types::Model)

      GPT4 = T.let(
        {
          id: "gpt-4:5",
          registry: "azure-openai",
          name: "gpt-4",
          original_name: "gpt-4",
          friendly_name: "gpt-4",
          task: "chat-completion",
          publisher: "OpenAI",
          publisherDisplayName: "Azure OpenAI Service",
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
          publisherSlug: "openai",
          capabilities: {
            jsonSchemaStructuredOutput: false,
            tokenCounting: true,
            streaming: true,
            streamingOptions: true,
            structuredOutput: true,
          },
          isRestricted: false,
          isBillable: false,
          isCustom: false,
        }, DefaultAndCustomModels::Types::Model)

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
        }, DefaultAndCustomModels::Types::ModelSchema
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
        }, DefaultAndCustomModels::Types::ModelSchema
      )
    end
  end
end
