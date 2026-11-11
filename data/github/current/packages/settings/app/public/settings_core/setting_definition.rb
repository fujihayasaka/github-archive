# typed: strict
# frozen_string_literal: true

module SettingsCore
  # A SettingDefinition defines how a particular setting is evaluated across a hierarchy of targetable resources.
  # Each setting should override this class to provide custom evaluation logic.
  class SettingDefinition
    extend T::Helpers
    extend T::Generic

    # An intermediate type used during evaluation. This could be the same as Result, but doesn't have to be.
    EvaluationContext = type_member
    # The final type returned by the setting definition.
    Result = type_member

    abstract!

    # A unique name for this setting definition.
    sig { abstract.returns(String) }
    def name; end

    sig { abstract.returns(DomainAccessorBase) }
    def domain; end

    sig { returns(T::Array[SettingGroup[EvaluationContext, Result]]) }
    def groups
      groups = []
      parts = name.split(".")
      parts.each_with_index do |_, index|
        group_names = T.must(parts[0..index]).join(".")
        group = domain.group_by_name(group_names)
        groups << group if group
      end

      groups
    end

    # The default value for the setting, used if no value is set in the hierarchy.
    sig { abstract.returns(Result) }
    def default_value; end

    sig { overridable.returns(T::Array[RuleEvaluator[EvaluationContext]]) }
    def rule_handlers
      []
    end

    # Called before evaluating a setting at a resource. Combines the contexts from parent resources into a single context.
    # Most implementations will only support a single parent resource and therefore will just the single parent's context
    sig { abstract.params(parent_contexts: T::Array[EvaluationContext]).returns(EvaluationContext) }
    def context_from_parents(parent_contexts); end

    # Called to evaluate the setting at a particular resource, given the context from its parents.
    # The implementation should return the updated context after applying the settings at this resource.
    sig { abstract.params(evaluation_graph: Graph[EvaluationContext], context: EvaluationContext).returns(EvaluationContext) }
    def evaluate_at_resource(evaluation_graph, context); end

    # Called after the entire graph has been evaluated to produce the final result for this setting definition.
    sig { abstract.params(evaluation_context: T.nilable(EvaluationContext)).returns(Result) }
    def finalize_value(evaluation_context); end

    # By default, Targetable objects define their hierarchy
    # To provide a custom hierarchy, override this method
    sig { overridable.params(targetable: Targeting::Targetable).returns(T::Array[Targeting::Targetable]) }
    def parent_resources(targetable)
      targetable.async_memoized_targetable_parents.sync
    end

    # Called before rule validations are run. Any global logic to validate changes to the context should be implemented here.
    # Rules can further restrict or allow changes to the context.
    sig { overridable.params(old: EvaluationContext, new: EvaluationContext).returns(T.any(ValidationResult::None, ValidationResult::InvalidDefault)) }
    def default_validator(old, new)
      ValidationResult::None
    end

    sig { params(targetable: Targeting::Targetable).returns(Graph[EvaluationContext]) }
    def get_result_graph(targetable)
      graph = evaluation_graph(targetable)
      settings = domain.load_settings(graph.all_resources, self.name)
      populate_graph(graph, settings)

      evaluate_graph(graph)

      graph
    end

    sig { params(targetable: Targeting::Targetable).returns(Result) }
    def get_result(targetable)
      graph = get_result_graph(targetable)

      if T.unsafe(targetable).respond_to?(:feature_flag_enabled?) && T.unsafe(targetable).feature_flag_enabled?(:setting_rules_log_evaluation, default: false)
        graph.log_evaluation(name)
      end

      finalize_value(graph.final_value)
    end

    class SettingsDefinitionError < StandardError; end

    class ValidationResult < T::Enum
      enums do
        Valid = new
        Invalid = new
        InvalidDefault = new
        None = new
      end

      sig { returns(T::Boolean) }
      def allowed?
        self != Invalid && self != InvalidDefault
      end
    end

    private

    sig { params(graph: Graph[EvaluationContext]).void }
    def evaluate_graph(graph)
      # All parents must be evaluated first
      unless graph.evaluatable?
        graph.parents.each do |parent_graph|
          evaluate_graph(parent_graph)
        end
      end

      # Combine contexts from parents
      context = context_from_parents(graph.parents.map(&:final_value).compact)

      # Find matching rules
      rules = graph.parents.flat_map(&:rules)
      matching_rules = rules.filter do |rule|
        rule.condition_expression.evaluate(graph.node) == IConditionExpression::EvaluateResult::MATCH
      end

      # Perform mutations from the parent before evaluating at this node
      matching_rules.each do |rule|
        rule_impl = find_rule_handler(rule)
        next unless rule_impl
        context = rule_impl.perform_rule(self, context, rule)
      end

      graph.inherited_value = context

      # Evaluate at this node
      updated_context = evaluate_at_resource(graph, context)

      # Check if changes are allowed by all rules
      validation_result = T.let(default_validator(context, updated_context), SettingsCore::SettingDefinition::ValidationResult)
      matching_rules.each do |rule|
        rule_impl = find_rule_handler(rule)
        next unless rule_impl
        validation_result = rule_impl.validation_result(self, context, updated_context, rule, validation_result)
      end

      graph.final_value = validation_result.allowed? ? updated_context : context
    end

    sig { params(graph: Graph[T.untyped], all_settings: T::Array[ISetting]).void }
    def populate_graph(graph, all_settings)
      node_settings = all_settings.select { |s| s.targetable == graph.node }
      graph.settings.concat(node_settings)

      graph.parents.each do |parent_graph|
        populate_graph(parent_graph, all_settings)
      end
    end

    sig { params(targetable: Targeting::Targetable).returns(Graph[T.untyped]) }
    def evaluation_graph(targetable)
      parent_resources = parent_resources(targetable)
      if parent_resources.empty?
        Graph.new(name, targetable)
      else
        sub_graphs = parent_resources.map do |res|
          graph = evaluation_graph(res)
        end

        Graph.new(name, targetable, sub_graphs)
      end
    end

    sig { params(rule: IRule).returns(T.nilable(RuleEvaluator[EvaluationContext])) }
    def find_rule_handler(rule)
      if rule.setting&.name == self.name
        rule_handlers.find { |impl| impl.rule_type == rule.rule_type }
      else
        groups.each do |group|
          if rule.setting&.name == group.name
            return group.rule_handlers.find { |impl| impl.rule_type == rule.rule_type }
          end
        end

        nil
      end
    end
  end
end
