# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  class RuleDefinition
    extend T::Helpers
    extend T::Generic

    Result = type_member { { upper: BasicObject } }

    abstract!

    sig { returns(String) }
    attr_reader :rule_type

    sig { returns(ResourceDefinition::ResourceType) }
    attr_reader :applies_to

    sig { params(rule_type: String, applies_to: ResourceDefinition::ResourceType).void }
    def initialize(rule_type, applies_to:)
      @rule_type = rule_type
      @applies_to = applies_to
    end

    sig { abstract.returns(RuleEngine::ParameterSchema::Object) }
    def parameter_schema; end

    sig { abstract.returns(T::Array[TargetingAttributeDescriptor]) }
    def targeting_attributes; end

    sig do
      abstract.params(
        definition: SettingDefinition[T.untyped, Result],
        evaluation_context: EvaluationContext[Result],
        rule: IRule
      ).void
    end
    def perform_rule(definition, evaluation_context, rule); end

    class ValueType < T::Enum
      enums do
        TEXT = new("text")
        SEARCH = new("search")
        SELECT = new("select")
      end
    end

    class TargetingAttributeDescriptor < T::Struct
      const :attribute, String
      const :display_name, String
      const :operations, T::Array[IConditionExpression::Operation]
      const :value_type, ValueType
    end
  end
end
