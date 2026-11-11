# typed: strict
# frozen_string_literal: true

module SettingsCore
  # Represents a group of related settings.
  # Settings groups can have their own rules that apply to all (or some) settings in the group
  # Groups can be evaluated together to produce a group output (TODO)
  class SettingGroup
    extend T::Helpers
    extend T::Generic

    abstract!

    SupportedEvaluationContexts = type_member
    SupportedResults = type_member

    sig { returns(String) }
    attr_reader :name

    sig { returns(T::Array[T.any(SettingGroup[SupportedEvaluationContexts, T.untyped], SettingDefinition[SupportedEvaluationContexts, SupportedResults])]) }
    attr_reader :definitions

    sig do
      params(
        name: String,
        definitions: T::Array[T.any(SettingGroup[SupportedEvaluationContexts, T.untyped], SettingDefinition[SupportedEvaluationContexts, SupportedResults])]
      ).void
    end
    def initialize(name, definitions)
      @name = name
      @definitions = definitions
    end

    sig { overridable.returns(T::Array[RuleEvaluator[SupportedEvaluationContexts]]) }
    def rule_handlers
      []
    end

  end
end
