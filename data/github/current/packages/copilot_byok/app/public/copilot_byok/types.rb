# typed: strict
# frozen_string_literal: true

module CopilotByok
  class Types
    CustomKey = T.type_alias do
      {
        id: Integer,
        name: String,
        provider: String,
        totalModels: Integer,
        deploymentUrl: T.nilable(String), # Only for AzureAI provider
      }
    end

    # Keep in sync with `CustomModel` in packages/copilot-byok-settings/types.ts in github/github-ui
    CustomModel = T.type_alias do
      {
        id: Integer,
        slug: String,
        name: T.nilable(String),
        customKeyId: Integer,
        enabled: T::Boolean,
      }
    end

    class SelectorCustomModel < T::Struct
      prop :slug, String
      prop :name, T.nilable(String), default: nil
      prop :deprecated, T.nilable(T::Boolean), default: nil
      prop :fresh, T.nilable(T::Boolean), default: nil
      prop :createdAt, T.nilable(Time), default: nil
      prop :id, T.nilable(Integer), default: nil
      prop :selected, T.nilable(T::Boolean), default: nil
    end
  end
end
