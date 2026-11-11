# typed: strict
# frozen_string_literal: true

module CopilotByok
  class Types
    # Keep in sync with `CustomKey` in packages/copilot-byok-settings/types.ts in github/github-ui
    CustomKey = T.type_alias do
      {
        id: Integer,
        name: String,
        provider: String,
        totalModels: Integer,
        editable: T.nilable(T::Boolean),
        ownerName: String,
        deploymentUrl: T.nilable(String), # Only for AzureAI provider
        baseUrl: T.nilable(String), # Only for OpenAI Compatible provider
        region: T.nilable(String), # AWS Bedrock
      }
    end

    CustomKeyProviderData = T.type_alias do
      T.any(
        CopilotByok::ProviderData::CustomKey::AwsBedrock,
        CopilotByok::ProviderData::CustomKey::OpenAICompatible,
        CopilotByok::ProviderData::CustomKey::MicrosoftFoundry,
        T::Hash[String, T.untyped]
      )
    end

    # Keep in sync with `CustomModel` in packages/copilot-byok-settings/types.ts in github/github-ui
    CustomModel = T.type_alias do
      {
        id: Integer,
        slug: String,
        name: T.nilable(String),
        customKeyId: Integer,
        editable: T.nilable(T::Boolean),
        enabled: T::Boolean,
        toolCalling: T::Boolean,
        vision: T::Boolean,
        thinking: T::Boolean,
        streaming: T::Boolean,
        maxInputTokens: T.nilable(Integer),
        maxOutputTokens: T.nilable(Integer),
        maxContextWindow: T.nilable(Integer),
        endpointType: String,
      }
    end

    CustomModelProviderData = T.type_alias do
      T.any(
        CopilotByok::ProviderData::CustomModel::AwsBedrock,
        T::Hash[String, T.untyped]
      )
    end

    Organization = T.type_alias do
      {
        id: Integer,
        displayLogin: String,
        avatarUrl: String,
        name: String,
      }
    end

    # Keep in sync with TypeScript type `EnterpriseCustomModelAccessStatus` in
    # packages/copilot-byok-enterprise-settings/types.ts in github/github-ui
    EnterpriseCustomModelAccessStatus = T.type_alias do
      {
        allowedOrgIds: T.nilable(T::Array[Integer]),
        enabledForAllOrgs: T::Boolean,
      }
    end

    # Keep in sync with `SelectorCustomModel` in packages/copilot-byok-settings/types.ts in github/github-ui
    class SelectorCustomModel < T::Struct
      prop :slug, String
      prop :name, T.nilable(String), default: nil
      prop :deprecated, T.nilable(T::Boolean), default: nil
      prop :fresh, T.nilable(T::Boolean), default: nil
      prop :createdAt, T.nilable(Time), default: nil
      prop :id, T.nilable(Integer), default: nil
      prop :selected, T.nilable(T::Boolean), default: nil
      prop :maxOutputTokens, T.nilable(Integer), default: nil
      prop :additionalData, T.nilable(T::Hash[String, T.untyped]), default: nil
    end
  end
end
