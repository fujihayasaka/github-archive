# typed: strict
# frozen_string_literal: true

module ModelsByok
  class Types

    # Keep in sync with ui/packages/models-byok-settings/types.ts#CustomKey
    CustomKey = T.type_alias do
      {
        id: Integer,
        name: String,
        provider: String,
        totalModels: Integer,
      }
    end

    # Keep in sync with `ModelEnabled` in ui/packages/models-byok-settings/types.ts
    CustomModelEnabled = T.type_alias do
      {
        copilot: T::Boolean,
        models: T::Boolean,
      }
    end

    # Keep in sync with ui/packages/models-byok-settings/types.ts#CustomModel
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
    SelectorCustomModel = T.type_alias do
      {
        slug: String,
        name: T.nilable(String),
        deprecated: T.nilable(T::Boolean),
        fresh: T.nilable(T::Boolean),
        createdAt: T.nilable(Time),
      }
    end
  end
end
