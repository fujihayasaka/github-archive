# typed: strict
# frozen_string_literal: true

# Shared module for building capability attributes from frontend model data
# Used by CreateCustomKey and UpdateCustomKey services to transform camelCase
# frontend capability data into snake_case ActiveRecord attributes.
module CopilotByok::Concerns::CapabilityAttributesBuilder
  extend T::Helpers

  # Frontend capability field names (camelCase)
  CAPABILITY_FIELDS = T.let(
    [:toolCalling, :vision, :thinking, :maxInputTokens, :maxOutputTokens].freeze,
    T::Array[Symbol]
  )

  # Check if the model hash contains any capability-related fields
  sig { params(model_data: T.any(T::Hash[T.untyped, T.untyped], ActionController::Parameters)).returns(T::Boolean) }
  def has_capability_data?(model_data)
    CAPABILITY_FIELDS.any? { |field| model_data.key?(field) }
  end

  # Build capability attributes hash for a model
  # @param model_data [Hash, ActionController::Parameters] The incoming model data from frontend
  # @param existing_capability [CustomModelCapability, nil] Optional existing capability for updates
  # @return [Hash] Capability attributes ready for ActiveRecord nested attributes
  sig do
    params(
      model_data: T.any(T::Hash[T.untyped, T.untyped], ActionController::Parameters),
      existing_capability: T.nilable(CopilotByok::CustomModelCapability)
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def build_capability_attributes(model_data, existing_capability: nil)
    capability_attrs = {}

    # Preserve existing capability ID if updating
    if existing_capability
      capability_attrs[:id] = existing_capability.id
    end

    # Map boolean capability flags
    capability_attrs[:tool_calling] = model_data[:toolCalling] || false
    capability_attrs[:vision] = model_data[:vision] || false
    capability_attrs[:thinking] = model_data[:thinking] || false

    # Map token limits (only if provided)
    if model_data.key?(:maxInputTokens)
      capability_attrs[:max_input_tokens] = model_data[:maxInputTokens]
    end

    if model_data.key?(:maxOutputTokens)
      capability_attrs[:max_output_tokens] = model_data[:maxOutputTokens]
    end

    capability_attrs
  end
end
