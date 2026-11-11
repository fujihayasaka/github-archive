# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  module Definitions
    # A reference implementation of a boolean setting definition.
    # Use to represent settings that can be true or false.
    # This implementation supports two modes of operation:
    # - ParentWins: If a parent resource has a value set, that value takes precedence over any child resource values.
    # - ChildWins: Child resource values take precedence over parent resource values.
    class BooleanSettingDefinition < SettingDefinition
      abstract!

      SupportedResource = type_member
      ResultType = type_member { { fixed: T::Boolean } }

      sig { override.params(resource: SupportedResource, context: EvaluationContext[ResultType]).void }
      def modify_context(resource, context)
        # In ParentWins mode, restrict descendants to the same value so children
        # cannot override what was set here.
        if mode == InheritanceMode::ParentWins && !(value = context.current_value).nil?
          context.set_allowed_values([value])
        end
      end

      sig { override.params(resource: SupportedResource, value: T.untyped).returns(T.nilable(ResultType)) }
      def coerce_value(resource, value)
        if value.is_a?(String) && %w[true false].include?(value.downcase)
          ActiveModel::Type::Boolean.new.cast(value)
        elsif value.is_a?(TrueClass) || value.is_a?(FalseClass)
          value
        else
          nil
        end
      end

      sig { abstract.returns(InheritanceMode) }
      def mode; end

      class InheritanceMode < T::Enum
        enums do
          ParentWins = new("parent_wins")
          ChildWins = new("child_wins")
        end
      end

      # Sets the setting value to a boolean when conditions match.
      # Parameters: { "value" => true | false }
      class SetRule < RuleDefinition
        Result = type_member { { fixed: T::Boolean } }

        sig { params(mode: InheritanceMode, applies_to: ResourceDefinition::ResourceType, targeting_attributes: T::Array[TargetingAttributeDescriptor]).void }
        def initialize(mode:, applies_to:, targeting_attributes: [])
          super("set", applies_to:)
          @mode = mode
          @targeting_attributes = targeting_attributes
        end

        sig { override.returns(T::Array[TargetingAttributeDescriptor]) }
        def targeting_attributes
          @targeting_attributes
        end

        sig { override.returns(RuleEngine::ParameterSchema::Object) }
        def parameter_schema
          schema = RuleEngine::ParameterSchema::Object.root
          schema.add_field(RuleEngine::ParameterSchema::Field.new(name: "value", display_name: "Value", type: "boolean",
            description: "The value to override the setting with", required: true))
          schema
        end

        sig { override.params(definition: SettingsCoreV2::SettingDefinition[T.untyped, Result], context: SettingsCoreV2::EvaluationContext[Result], rule: IRule).void }
        def perform_rule(definition, context, rule)
          new_value = rule.param("value")
          return if new_value.nil?

          context.set_current_value(new_value)
          if @mode == InheritanceMode::ParentWins
            context.set_allowed_values([new_value])
          end
        end
      end
    end
  end
end
