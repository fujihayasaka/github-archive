# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  # Used to evaluate an inheritance graph of settings
  class GraphResolver
    extend T::Generic

    SupportedResource = type_member
    Result = type_member { { upper: BasicObject } }

    sig { returns(SupportedResource) }
    attr_reader :resource

    sig { returns(String) }
    attr_reader :setting_name

    sig { returns(T::Array[GraphResolver[SupportedResource, Result]]) }
    attr_reader :parent_evaluators

    sig { params(domain: DomainAccessorBase, resource: SupportedResource, definition: SettingDefinition[SupportedResource, Result], setting_name: String).void }
    def initialize(domain, resource, definition, setting_name)
      @domain = domain
      @resource = resource
      @definition = definition
      @setting_name = setting_name

      @rules_to_apply = T.let([], T::Array[IRule])

      @parent_evaluators = T.let([], T::Array[GraphResolver[SupportedResource, Result]])
      @initial_value = T.let(nil, T.untyped)
    end

    sig { returns(EvaluationContext[Result]) }
    def evaluate_setting
      build

      all_settings = @domain.load_settings(targets_to_names)
      populate_settings(all_settings)

      context = evaluate

      if case @resource when GitHub::VexiActor then @resource.feature_flag_enabled?(:setting_rules_log_evaluation, default: false) else false end
        log_evaluation(context)
      end

      context
    end

    sig { void }
    def build
      parents = @definition.resource_definitions.find { |rd| rd.is_resource?(@resource) }&.parents(@resource) || []
      parents.each do |parent_resource|
        definition = @domain.definition_by_name(@setting_name)
        next unless definition
        evaluator = definition.resolver(@domain, parent_resource, @setting_name)
        evaluator.build
        @parent_evaluators << evaluator
      end
    end

    # Builds a mapping of resource → setting names needed for evaluation.
    # Each resource is mapped only to the names it actually needs.
    sig { returns(T::Hash[T.untyped, T::Array[String]]) }
    def targets_to_names
      mapping = Hash.new { |h, k| h[k] = Set.new }

      # This resource needs its own setting name
      mapping[@resource].add(@setting_name)

      # Merge in dependent evaluator mappings
      @parent_evaluators.each do |evaluator|
        evaluator.targets_to_names.each do |target, names|
          mapping[target].merge(names)
        end
      end

      mapping.transform_values(&:to_a)
    end

    sig { params(settings: T::Array[ISetting]).void }
    def populate_settings(settings)
      parent_evaluators.each { |evaluator| evaluator.populate_settings(settings) }

      matching_setting = settings.find do |setting|
        resources_match?(@resource, setting.resource) && setting.name == @setting_name
      end

      @initial_value = matching_setting ? matching_setting.value : nil

      # Only collect rules from settings belonging to this evaluator's rule sources
      rule_source_settings = settings.select do |setting|
        @parent_evaluators.any? { |de| resources_match?(de.resource, setting.resource) }
      end
      rule_source_settings.each do |setting|
        setting.rules.each do |rule|
          result = applies_rule?(rule, @resource)
          if result
            @rules_to_apply << rule
          end
        end
      end
    end

    sig { params(context: EvaluationContext[Result], parent: T.untyped).returns(T.nilable(Result)) }
    def inherited_value(context, parent = nil)
      @definition.inheritance_priority.each do |value|
        relevant_contexts = parent ? context.parent_contexts.select { |dc| resources_match?(dc.resource, parent) } : context.parent_contexts
        if context.is_value_allowed?(value) && relevant_contexts.any? { |dc| dc.current_value == value }
          return value
        end
      end
      nil
    end

    protected

    sig { returns(EvaluationContext[Result]) }
    def evaluate
      parent_contexts = @parent_evaluators.map do |evaluator|
        evaluator.evaluate
      end

      parent_contexts.each do |parent_context|
        @rules_to_apply.each do |rule|
          evaluator = @definition.rule_definitions.find { |handler| handler.rule_type == rule.rule_type }
          next unless evaluator
          evaluator.perform_rule(@definition, parent_context, rule)
        end
      end

      allowed_values_by_node_type = {}
      # intersection of allowed values by node type
      parent_contexts.each do |parent_context|
        parent_context.child_allowed_values.each do |node_type, values|
          if allowed_values_by_node_type[node_type].nil?
            allowed_values_by_node_type[node_type] = values
          else
            if values.nil?
              allowed_values_by_node_type[node_type] = nil
            else
              allowed_values_by_node_type[node_type] = allowed_values_by_node_type[node_type] & values
            end
          end
        end
      end
      current_node_allowed_values = allowed_values_by_node_type[T.unsafe(@resource).class] || allowed_values_by_node_type[nil]

      context = EvaluationContext[Result].new(@resource, @setting_name, nil, current_allowed_values: current_node_allowed_values, child_allowed_values: allowed_values_by_node_type, parent_contexts: parent_contexts)
      unless @initial_value.nil?
        coerced_value = @definition.coerce_value(@resource, @initial_value)
        # `coerce_value` returns nil for invalid values; check nil explicitly so
        # a valid falsy value (e.g. boolean `false`) is still applied.
        if case coerced_value; when nil then false; else true; end
          context.set_current_value(coerced_value)
        else
          GitHub.logger.error("Invalid setting value",
            "gh.setting.name": @setting_name,
            "gh.setting.resource_type": T.unsafe(@resource).class.name,
            "gh.setting.resource_id": T.unsafe(@resource).try(:id),
            "gh.setting.value": @initial_value
          )
        end
      end
      @definition.modify_context(@resource, context)

      # If the evaluator did not set a value, attempt to inherit from dependencies based on the defined priority.
      if (case context.current_value; when nil then true; else false; end) && context.parent_contexts.any?
        to_inherit = inherited_value(context)
        if case to_inherit; when nil then false; else true; end
          context.set_current_value(to_inherit)
        end
      end

      context
    end

    sig { params(context: EvaluationContext[Result]).void }
    def log_evaluation(context)
      attrs = T.let({
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.setting.resource_type": T.unsafe(@resource).class.name,
        "gh.setting.resource_id": T.unsafe(@resource).try(:id),
        "gh.setting.name": @setting_name,
        "gh.setting.result": context.current_value,
        "gh.setting.stored_value": @initial_value,
        "gh.setting.allowed_values": context.current_allowed_values,
        "gh.setting.parents_count": @parent_evaluators.size,
        "gh.setting.rules_applied_count": @rules_to_apply.size,
      }, T::Hash[Symbol, T.untyped])

      GitHub.logger.info("Settings evaluation", attrs)
    end

    # Compares two resources for equality, handling Targetable wrappers that may
    # be different instances wrapping the same internal record.
    sig { params(a: T.untyped, b: T.untyped).returns(T::Boolean) }
    def resources_match?(a, b)
      return true if a == b

      a_record = a.respond_to?(:internal_record) ? a.internal_record : a
      b_record = b.respond_to?(:internal_record) ? b.internal_record : b
      a_record == b_record
    end

    # Checks if a rule applies to a resource using the definition's condition matchers.
    # Falls back to Targetable evaluation for legacy support, or applies unconditionally
    # if no matchers are available.
    sig { params(rule: IRule, resource: T.untyped).returns(T::Boolean) }
    def applies_rule?(rule, resource)
      expr = rule.condition_expression
      resource_def = @definition.resource_definitions.find { |rd| rd.is_resource?(resource) }
      return false unless resource_def

      rule_evaluator = @definition.rule_definitions.find { |rd| rd.rule_type == rule.rule_type }
      return false unless rule_evaluator
      return false unless resource_def.resource_type == rule_evaluator.applies_to

      expr.evaluate(resource, resource_def.matchers, overrides: @domain.attribute_overrides)
    end
  end
end
