# typed: strict
# frozen_string_literal: true

module Marketplace
  class Types
    extend T::Helpers
    extend T::Sig

    class ListingTypes < T::Enum
      enums do
        MarketplaceListing = new("marketplace_listing")
        RepositoryAction = new("repository_action")
      end
    end

    SerializedAppListing = T.type_alias do
      {
        bgColor: String,
        copilotApp: T::Boolean,
        documentationUrl: T.nilable(String),
        extendedDescription: T.nilable(String),
        fullDescription: T.nilable(String),
        id: Integer,
        installationCount: Integer,
        isVerifiedOwner: T::Boolean,
        listingLogoUrl: T.nilable(String),
        name: String,
        ownerLogin: T.nilable(String),
        pricingUrl: T.nilable(String),
        primaryCategory: T.nilable(String),
        privacyPolicyUrl: T.nilable(String),
        secondaryCategory: T.nilable(String),
        shortDescription: T.nilable(String),
        slug: String,
        statusUrl: T.nilable(String),
        supportUrl: T.nilable(String),
        tosUrl: T.nilable(String),
        type: String
      }
    end

    SerializedActionListing = T.type_alias do
      {
        categories: T::Array[String],
        color: String,
        description: T.nilable(String),
        iconSvg: T.nilable(String),
        id: Integer,
        isVerifiedOwner: T::Boolean,
        name: String,
        ownerLogin: T.nilable(String),
        slug: T.nilable(String),
        stars: Integer,
        type: String,
      }
    end

    Listing = T.type_alias do
      T.any(SerializedAppListing, SerializedActionListing)
    end

    Search = T.type_alias do
      {
        results: T::Array[Marketplace::Types::Listing],
        total: Integer,
        totalPages: Integer
      }
    end

    SerializedCategory = T.type_alias do
      {
        name: String,
        slug: String,
        description_html: String
      }
    end

    SerializedScreenshot = T.type_alias do
      {
        id: Integer,
        src: String,
        caption: T.nilable(String),
        alt_text: T.nilable(String)
      }
    end

    PlanInfo = T.type_alias do
      {
        any_account_eligible_for_free_trial: T::Boolean,
        can_sign_end_user_agreement: T::Boolean,
        emu_owner_but_not_admin: T::Boolean,
        end_user_agreement: T.nilable({
          html: String,
          id: Integer,
          name: String,
          user_signed_at: T.nilable(ActiveSupport::TimeWithZone),
          version: String,
        }),
        free_trial_length: String,
        free_trials_used: T::Boolean,
        installation_url_requirement_met: T::Boolean,
        is_buyable: T::Boolean,
        is_logged_in: T::Boolean,
        is_regular_emu_user: T::Boolean,
        is_user_billed_monthly: T::Boolean,
        listing_by_github: T::Boolean,
        order_preview: { quantity: T.nilable(Integer) },
        organizations: T::Array[{ display_login: String, has_extensibility_access: T::Boolean, image: T.nilable(String) }],
        plans: T::Array[Plan],
        selected_account: T.nilable(String),
        selected_plan_id: T.nilable(String),
        subscription_item: { on_free_trial: T.nilable(T::Boolean) },
        support_email: T.nilable(String),
        user_can_edit_listing: T::Boolean,
        viewer_free_trial_days_left: T.nilable(Integer),
        viewer_has_purchased: T::Boolean,
        any_orgs_purchased: T::Boolean,
        viewer_billed_organizations: T::Array[String],
        viewer_has_purchased_for_all_organizations: T::Boolean,
        installed_for_viewer: T::Boolean,
        plan_id_by_login: T::Hash[String, String],
        current_user: T.nilable({ display_login: String, has_extensibility_access: T::Boolean, image: T.nilable(String) })
      }
    end

    Plan = T.type_alias do
      {
        id: String,
        name: String,
        description: String,
        yearly_price_in_cents: Integer,
        monthly_price_in_cents: Integer,
        per_unit: T::Boolean,
        unit_name: T.nilable(String),
        is_paid: T::Boolean,
        has_free_trial: T::Boolean,
        price: String,
        direct_billing: T::Boolean,
        for_organizations_only: T::Boolean,
        for_users_only: T::Boolean,
        bullets: T::Array[String]
      }
    end

    module AzureModels
      RenderableModel = T.type_alias do
        {
          model: AzureModels::Model,
          schema: AzureModels::ModelSchema
        }
      end

      MarkdownTocItem = T.type_alias do
        {
          level: Integer,
          text: String,
          anchor: String
        }
      end

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
          samples: T.nilable(T::Hash[String, T::Array[T::Hash[String, T.untyped]]]),
          summary: String,
          model_family: String,
          model_version: Integer,
          notes: String,
          tags: T::Array[String],
          rate_limit_tier: T.nilable(String),
          supported_languages: T::Array[String],
          max_output_tokens: T.nilable(Integer),
          max_input_tokens: Integer,
          training_data_date: T.nilable(String),
          logo_url: T.nilable(String),
          evaluation: T.nilable(String),
          license_description: T.nilable(String),
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
          capabilities: T::Hash[T.untyped, T.untyped],
          type: String,
          version: String,
          behavior: String,
          parameters: T::Array[T::Hash[T.untyped, T.untyped]],
        }
      end

      module Static
        GPT4o = T.let(
          {
            id: "gpt-4o:1",
            registry: "azure-openai",
            name: "gpt-4o",
            friendly_name: "gpt-4o",
            original_name: "gpt-4o",
            task: "chat-completion",
            publisher: "OpenAI",
            license: "",
            description: "## Model Family: GPT-4\n" + "\n" + "GPT-4o is OpenAI's most advanced model to date. This multimodal model handles both text and image inputs while generating text outputs. Matching the intelligence of GPT-4 Turbo, it is remarkably more efficient, delivering text at twice the speed and at half the cost. Additionally, GPT-4o exhibits the highest vision performance and excels in non-English languages compared to previous OpenAI models.\n" + "\n" + "> Note: You can deploy GPT-4o in the following US regions only at this time: eastus, eastus2, northcentralus, southcentralus, westus, westus3.\n",
            samples: {
              "inputs": [
                {
                  "messages": [
                    {
                      "role": "user",
                      "content": "What is the history of the Great Wall of China?"
                    }
                  ]
                }
              ]
            },
            summary: "",
            model_family: "gpt-4o",
            notes: "",
            model_version: 1,
            tags: [],
            rate_limit_tier: "high",
            supported_languages: ["English"],
            max_output_tokens: 4096,
            max_input_tokens: 131072,
            training_data_date: "2023-10-01T00:00:00+00:00",
            logo_url: "",
            evaluation: "",
            license_description: "",
          }, AzureModels::Model)

        GPT4 = T.let(
          {
            id: "gpt-4:5",
            registry: "azure-openai",
            name: "gpt-4",
            friendly_name: "gpt-4",
            original_name: "gpt-4",
            task: "chat-completion",
            publisher: "OpenAIDevault",
            license: "",
            description: "# This model can be deployed for inferencing.\n" + "\n" + "## Model family: GPT-4\n" + "\n" + "GPT-4 is a large multimodal model that accepts text or image inputs and outputs text. It can solve complex problems with greater accuracy than any of our previous models, thanks to its extensive general knowledge and advanced reasoning capabilities.\n" + "\n" + "## Model versions:\n" + "\n" + "GPT-4 provides a wide range of model versions to fit your business needs. Please note that AzureML Studio only supports the deployment of the gpt-4-0314 model version and AI Studio supports the deployment of all the model versions listed below.\n" + "\n" + "- **gpt-4-turbo-2024-04-09:** This is the GPT-4 Turbo with Vision GA model. The context window is 128,000 tokens, and it can return up to 4,096 output tokens. The training data is current up to December 2023.\n" + "\n" + "- **gpt-4-1106-preview (GPT-4 Turbo):** The latest gpt-4 model with improved instruction following, JSON mode, reproducible outputs, parallel function calling, and more. It returns a maximum of 4,096 output tokens. This preview model is not yet suited for production traffic. Context window: 128,000 tokens. Training Data: Up to April 2023.\n" + "\n" + "- **gpt-4-vision Preview (GPT-4 Turbo with vision):** This multimodal AI model enables users to direct the model to analyze image inputs they provide, along with all the other capabilities of GPT-4 Turbo. It can return up to 4,096 output tokens. As a preview model version, it is not yet suitable for production traffic. The context window is 128,000 tokens. Training data is current up to April 2023.\n" + "\n" + "- **gpt-4-0613:** gpt-4 model with a context window of 8,192 tokens. Training data up to September 2021.\n" + "\n" + "- **gpt-4-0314:** gpt-4 legacy model with a context window of 8,192 tokens. Training data up to September 2021. This model version will be retired no earlier than July 5, 2024.\n" + "\n" + "Learn more at https://learn.microsoft.com/en-us/azure/cognitive-services/openai/concepts/models",
            samples: {
              "inputs": [
                {
                  "messages": [
                    {
                      "role": "user",
                      "content": "What is the history of the Great Wall of China?"
                    }
                  ]
                }
              ]
            },
            summary: "",
            model_family: "gpt-4",
            notes: "",
            model_version: 5,
            tags: [],
            rate_limit_tier: "high",
            supported_languages: ["English"],
            max_output_tokens: 4096,
            max_input_tokens: 131072,
            training_data_date: "2023-10-01T00:00:00+00:00",
            logo_url: "",
            evaluation: "",
            license_description: "",
          }, AzureModels::Model)

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
          }, AzureModels::ModelSchema
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
          }, AzureModels::ModelSchema
        )
      end
    end
  end
end
