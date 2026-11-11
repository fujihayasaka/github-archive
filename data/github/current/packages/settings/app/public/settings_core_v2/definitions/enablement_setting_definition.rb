# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  module Definitions
    # A setting definition for settings that enable or disable features, with an optional "not set" state to allow for inheritance.
    # By default, children can override their parents value
    # The bundled rule (EnableRule) allows for enforcing enabled state on descendants, preventing overrides.
    class EnablementSettingDefinition < SettingDefinition
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
          ui_component: T.nilable(String),
          syncs_to: T.nilable(String),
        ).void
      end
      def initialize(setting_name:, display_name:, description:, providers:, resource_definitions:, ui_component: nil, syncs_to: nil)
        super(
          setting_name: setting_name,
          display_name: display_name,
          description: description,
          providers: providers,
          resource_definitions: resource_definitions,
          control_type: ControlType::TOGGLE,
          default_value: Value::NOT_SET,
          inheritance_priority: [Value::ENABLED, Value::DISABLED, Value::NOT_SET],
          ui_component: ui_component,
          syncs_to: syncs_to
        )
      end

      sig { override.params(resource: SupportedResource, context: EvaluationContext[ResultType]).void }
      def modify_context(resource, context)
        # Once a value is set at a resource, descendants should not be able to override it with NOT_SET
        current_allowed_values = context.current_allowed_values || inheritance_priority
        context.current_allowed_values = current_allowed_values - [Value::NOT_SET]
      end

      sig { override.params(resource: SupportedResource, value: T.untyped).returns(T.nilable(ResultType)) }
      def coerce_value(resource, value)
        Value.try_deserialize(value)
      end

      class EnableRule < RuleDefinition
        Result = type_member { { fixed: Value } }

        sig { params(applies_to: ResourceDefinition::ResourceType, targeting_attributes: T::Array[TargetingAttributeDescriptor]).void }
        def initialize(applies_to:, targeting_attributes:)
          super("enable", applies_to:)
          @targeting_attributes = targeting_attributes
        end

        sig { override.returns(T::Array[TargetingAttributeDescriptor]) }
        def targeting_attributes
          @targeting_attributes
        end

        sig { override.returns(RuleEngine::ParameterSchema::Object) }
        def parameter_schema
          schema = RuleEngine::ParameterSchema::Object.root
          schema.add_field(RuleEngine::ParameterSchema::Field.new(name: "enforce", display_name: "Enforce", type: "boolean",
            description: "Whether to enforce the override", required: false, default_value: false))
          schema
        end

        sig { override.params(definition: SettingsCoreV2::SettingDefinition[T.untyped, Result], context: SettingsCoreV2::EvaluationContext[Result], rule: IRule).void }
        def perform_rule(definition, context, rule)
          context.set_current_value(Value::ENABLED)
          if rule.param("enforce") == true
            context.set_allowed_values([Value::ENABLED])
          else
            # Once a value is set at a resource, descendants should not be able to override it with NOT_SET
            current_allowed_values = context.current_allowed_values || definition.inheritance_priority
            context.current_allowed_values = current_allowed_values - [Value::NOT_SET]
          end
        end
      end
    end
  end
end
