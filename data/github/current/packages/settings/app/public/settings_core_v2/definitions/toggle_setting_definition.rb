# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  module Definitions
    # A setting definition for settings that enable or disable features, with an optional "not set" state to allow for inheritance.
    # By default, children can override their parents value
    # Supports force enablement and disablement
    class ToggleSettingDefinition < SettingDefinition
      class Value < T::Enum
        enums do
          ENABLED = new("enabled")
          DISABLED = new("disabled")
          NOT_SET = new("not_set")
        end
      end

      SupportedResource = type_member
      ResultType = type_member { { fixed: Value } }

      sig do
        params(
          setting_name: String,
          display_name: String,
          description: String,
          providers: T::Array[String],
          resource_definitions: T::Array[ResourceDefinition],
          options: T.nilable(T::Array[OptionDescriptor]),
          ui_component: T.nilable(String),
          metadata: T.nilable(T::Hash[String, T.untyped]),
          syncs_to: T.nilable(String),
        ).void
      end
      def initialize(setting_name:, display_name:, description:, providers:, resource_definitions:, options: nil, ui_component: nil, metadata: nil, syncs_to: nil)
        super(
          setting_name: setting_name,
          display_name: display_name,
          description: description,
          control_type: ControlType::TOGGLE,
          default_value: Value::NOT_SET,
          inheritance_priority: [Value::DISABLED, Value::ENABLED, Value::NOT_SET],
          providers: providers,
          resource_definitions: resource_definitions,
          options: options,
          ui_component: ui_component,
          metadata: metadata,
          syncs_to: syncs_to,
        )
      end

      sig { override.params(resource: SupportedResource, context: EvaluationContext[ResultType]).void }
      def modify_context(resource, context)
        # Once a value is set at a resource, descendants should not be able to override it with NOT_SET
        current_allowed_values = context.current_allowed_values || inheritance_priority
        context.current_allowed_values = current_allowed_values - [Value::NOT_SET]
      end

      sig { override.returns(ResultType) }
      def default_value
        Value::NOT_SET
      end

      sig { override.returns(T::Array[ResultType]) }
      def inheritance_priority
        [Value::DISABLED, Value::ENABLED, Value::NOT_SET]
      end

      sig { override.params(resource: SupportedResource, value: T.untyped).returns(T.nilable(ResultType)) }
      def coerce_value(resource, value)
        Value.try_deserialize(value)
      end

      # A rule that overrides the setting value when conditions match.
      # Parameters: { "value" => "enabled" | "disabled", "enforce" => boolean }
      #
      # Subclasses configure the rule's applies_to + targeting_attributes when
      # constructing it from `rule_definitions`.
      class OverrideRule < RuleDefinition
        Result = type_member { { fixed: Value } }

        sig { params(applies_to: ResourceDefinition::ResourceType, targeting_attributes: T::Array[TargetingAttributeDescriptor]).void }
        def initialize(applies_to:, targeting_attributes: [])
          super("override", applies_to:)
          @targeting_attributes = targeting_attributes
        end

        sig { override.returns(T::Array[TargetingAttributeDescriptor]) }
        def targeting_attributes
          @targeting_attributes
        end

        sig { override.returns(RuleEngine::ParameterSchema::Object) }
        def parameter_schema
          schema = RuleEngine::ParameterSchema::Object.root
          schema.add_field(RuleEngine::ParameterSchema::Field.new(name: "value", display_name: "Value", type: "string",
            description: "The value to override the setting with", required: true,
            allowed_values: [Value::ENABLED.serialize, Value::DISABLED.serialize]))
          schema.add_field(RuleEngine::ParameterSchema::Field.new(name: "enforce", display_name: "Enforce", type: "boolean",
            description: "Whether to enforce the override", required: false, default_value: false))
          schema
        end

        sig { override.params(definition: SettingsCoreV2::SettingDefinition[T.untyped, Result], context: SettingsCoreV2::EvaluationContext[Result], rule: IRule).void }
        def perform_rule(definition, context, rule)
          override_value = rule.param("value")
          if override_value.present? && (value = Value.try_deserialize(override_value))
            context.set_current_value(value)
            if rule.param("enforce") == true
              context.set_allowed_values([value])
            end
          end
        end
      end
    end
  end
end
