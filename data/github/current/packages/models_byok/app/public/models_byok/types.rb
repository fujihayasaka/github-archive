# typed: strict
# frozen_string_literal: true

module ModelsByok
  class Types
    # Keep in sync with ui/packages/models-byok/types.ts#CustomKey
    CustomKey = T.type_alias do
      {
        id: Integer,
        name: String,
        provider: String,
        totalModels: Integer,
        deploymentUrl: T.nilable(String), # Only for AzureAI provider
      }
    end

    # Keep in sync with `ModelEnabled` in ui/packages/models-byok/types.ts
    CustomModelEnabled = T.type_alias do
      {
        copilot: T::Boolean,
        models: T::Boolean,
      }
    end

    # Keep in sync with ui/packages/models-byok/types.ts#CustomModel
    CustomModel = T.type_alias do
      {
        id: Integer,
        slug: String,
        name: T.nilable(String),
        customKeyId: Integer,
        enabled: CustomModelEnabled,
      }
    end

    # Subset of CustomModel used specifically in the ModelSelector: ui/packages/models-byok-settings/components/ModelSelectorConfig.tsx
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
