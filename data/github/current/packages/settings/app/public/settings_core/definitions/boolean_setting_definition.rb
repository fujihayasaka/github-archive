# typed: strict
# frozen_string_literal: true

module SettingsCore
  module Definitions
    # A reference implementation of a boolean setting definition.
    # Use to represent settings that can be true or false.
    # This implementation supports two modes of operation:
    # - ParentWins: If a parent resource has a value set, that value takes precedence over any child resource values.
    # - ChildWins: Child resource values take precedence over parent resource values.
    class BooleanSettingDefinition < SettingDefinition
      abstract!

      EvaluationContext = type_member { { fixed: T.nilable(T::Boolean) } }
      Result = type_member { { fixed: T::Boolean } }

      sig { override.params(parent_contexts: T::Array[EvaluationContext]).returns(EvaluationContext) }
      def context_from_parents(parent_contexts)
        if parent_contexts.size > 1
          raise SettingsDefinitionError, "Default setting implementations do not support multiple parents. Please implement your own SettingDefinition subclass."
        end
        parent_contexts.first || nil
      end

      sig { override.params(evaluation_graph: Graph[EvaluationContext], context: EvaluationContext).returns(EvaluationContext) }
      def evaluate_at_resource(evaluation_graph, context)
        if evaluation_graph.settings.empty?
          context
        else
          # There should only be one setting at this resource for this definition
          setting = T.must(evaluation_graph.settings.first)
          setting.value
        end
      end

      sig { override.params(old: EvaluationContext, new: EvaluationContext).returns(T.any(ValidationResult::None, ValidationResult::InvalidDefault)) }
      def default_validator(old, new)
        if !old.nil? && mode == Mode::ParentWins && old != new
          ValidationResult::InvalidDefault
        else
          ValidationResult::None
        end
      end

      sig { override.params(evaluation_context: EvaluationContext).returns(Result) }
      def finalize_value(evaluation_context)
        (val = evaluation_context).nil? ? default_value : val
      end

      sig { override.returns(T::Array[RuleEvaluator[EvaluationContext]]) }
      def rule_handlers
        [
          SimpleRuleMutator[EvaluationContext].new("set") do |_, current_value, rule|
            params = rule.parameters
            if params["value"].nil?
              current_value
            else
              params["value"]
            end
          end,
          SimpleRuleValidator[EvaluationContext].new("allow_set") do |_, _, _|
            # Does not take parameter, allow_set always allows changes for boolean settings
            ValidationResult::Valid
          end
        ]
      end

      sig { abstract.returns(Mode) }
      def mode; end

      class Mode < T::Enum
        enums do
          ParentWins = new("parent_wins")
          ChildWins = new("child_wins")
        end
      end
    end
  end
end
