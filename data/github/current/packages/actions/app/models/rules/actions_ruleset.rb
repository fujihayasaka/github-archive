# typed: true
# frozen_string_literal: true

require "hashdiff"

module Rules
  class ActionsRuleset < ApplicationRecord::ActionsEnvironments
    include GitHub::Memoizer
    include RuleEngine::Timing
    extend RuleEngine::Timing
    include RuleEngine::IRuleset

    sig { returns(RuleEngine::RulesetImplementationPayload) }
    def self.impl_payload
      RuleEngine::RulesetImplementationPayload.new(
        ruleset_class: "Rules::ActionsRuleset",
        rule_condition_class: "Rules::ActionsRuleCondition",
        rule_configuration_class: "Rules::ActionsRuleConfiguration",
        ruleset_history_class: "Rules::ActionsRulesetHistory",
        ruleset_bypass_actor_class: nil,
        ruleset_association_name: "actions_ruleset"
      )
    end
    include RuleEngine::RulesetBase

    RULESET_LIMIT = 75
    RULESET_SECOND_LIMIT = 200

    self.table_name = "actions_rulesets"

    after_commit :append_history, on: [:create, :update]

    validates_uniqueness_of :name, scope: [:source], case_sensitive: false, message: "must be unique"
    before_validation :strip_whitespace
    validates_presence_of :name, message: "cannot be empty"
    validates_presence_of :source

    # Actions rulesets only support the "actions" target
    enum :target, { actions: 0 }, prefix: :targets

    ENFORCEMENT_DISPLAY_VALUES = {
      disabled: :disabled,
      enabled: :active,
      evaluate: :evaluate
    }.with_indifferent_access.freeze
    enum :enforcement, { disabled: 0, enabled: 1, evaluate: 2 }
    scope :not_disabled, -> { where.not(enforcement: :disabled) }
    scope :not_enabled, -> { where.not(enforcement: :enabled) }

    validate :ensure_rules_valid
    validate :ensure_conditions_valid
    validate :ensure_valid_plan
    validate :ensure_ruleset_limit_not_exceeded, on: :create
    validate :ensure_valid_source
    validate :ensure_valid_target

    def strip_whitespace
      self[:name] = self[:name]&.strip
    end

    def display_source_type
      definition.display_type
    end

    def display_source_name
      definition.display_source_name
    end

    sig { params(source: T.untyped).returns(Integer) }
    def self.ruleset_limit_count(source)
      if source.ruleset_second_limit_enabled?
        RULESET_SECOND_LIMIT
      else
        RULESET_LIMIT
      end
    end

    sig { override.params(source: T.untyped).returns(T::Boolean) }
    def self.limit_reached?(source)
      where(source: source).count >= ruleset_limit_count(source)
    end

    sig do
      override.params(
        source: T.untyped,
        include_parents: T::Boolean,
        targets: T.nilable(T::Array[String]),
        check_conditions_on_parent_rulesets: T::Boolean
      ).returns(T::Array[RuleEngine::IRuleset])
    end
    def self.load_for(source:, include_parents: false, targets: nil, check_conditions_on_parent_rulesets: true)
      trace_time("actions_ruleset.load_for", tags: ["source_type:#{source.class.name}", "include_parents:#{include_parents}", "targets:#{targets}"]) do
        sources = [source]

        if include_parents
          sources |= source.inherited_sources
        end

        rulesets = self.where(source: sources).order(source_type: :desc).includes(:rule_configurations, :conditions)

        GitHub::PrefillAssociations.prefill_associations(rulesets, :source, available_records: sources)

        rulesets = rulesets.filter do |ruleset|
          ruleset.definition.applies_to_targets?(targets) &&
          (!check_conditions_on_parent_rulesets || ruleset.definition.applies_to_source?(ruleset, source))
        end

        rulesets
      end
    end

    sig { params(new_conditions: T::Array[{ target: String, parameters: T.untyped }]).returns(T::Boolean) }
    def upsert_conditions(new_conditions)
      conditions_added = []
      @conditions_added = T.let(conditions_added, T.nilable(T::Array[RuleEngine::RuleConditionBase]))
      conditions_updated = []
      @conditions_updated = T.let(conditions_updated, T.nilable(T::Array[RuleEngine::RuleConditionBase]))
      conditions_deleted = []
      @conditions_deleted = T.let(conditions_deleted, T.nilable(T::Array[RuleEngine::RuleConditionBase]))

      existing_conditions_lookup = conditions.index_by { |condition| condition[:target] }
      new_conditions_lookup = T.let({}, T::Hash[String, { target: String, parameters: T.untyped }])

      new_conditions.map(&:deep_symbolize_keys).each do |condition_hash|
        key = condition_hash[:target].to_s
        new_conditions_lookup[key] = condition_hash

        if existing_conditions_lookup.key?(key)
          condition = existing_conditions_lookup[key]
          condition.parameters = condition_hash[:parameters] || {}

          next unless condition.changed?
          next if condition.changed_attributes.keys == ["parameters"] && Hashdiff.diff(condition.attributes["parameters"] || {}, condition.changed_attributes["parameters"] || {}).empty?

          raise RuleEngine::IRuleset::ConditionValidationError.new(condition, condition.parameter_errors) if !condition.valid? && condition.parameter_errors&.any?

          condition.save!

          conditions_updated << condition
          next
        end

        condition = self.conditions.build(
          target: condition_hash[:target],
          parameters: condition_hash[:parameters] || {},
        )

        raise RuleEngine::IRuleset::ConditionValidationError.new(condition, condition.parameter_errors) if !condition.valid? && condition.parameter_errors&.any?

        condition.save!

        conditions_added << condition
      end

      existing_conditions_lookup.each do |key, condition|
        next if new_conditions_lookup.key?(key)

        self.conditions.destroy(condition)

        conditions_deleted << condition
      end

      was_changed = conditions_added.any? || conditions_updated.any? || conditions_deleted.any?
      if persisted? && was_changed
        touch_later
      end
      was_changed
    end

    sig { params(new_rules: T::Array[{ rule_type: String, parameters: T.untyped }], apply_default_parameters: T::Boolean, remove_unknown_parameters: T::Boolean, actor_id: T.nilable(Integer)).returns(T::Boolean) }
    def upsert_rules(new_rules, apply_default_parameters: false, remove_unknown_parameters: false, actor_id: nil)
      rules_added = []
      @rules_added = T.let(rules_added, T.nilable(T::Array[RuleEngine::RuleConfigurationBase]))
      rules_updated = []
      @rules_updated = T.let(rules_updated, T.nilable(T::Array[RuleEngine::RuleConfigurationBase]))
      rules_deleted = []
      @rules_deleted = T.let(rules_deleted, T.nilable(T::Array[RuleEngine::RuleConfigurationBase]))

      existing_rules_lookup = rule_configurations.index_by(&:rule_type)
      new_rules_lookup = T.let({}, T::Hash[String, { rule_type: String, parameters: T.untyped }])

      new_rules.map(&:deep_symbolize_keys).each do |rule_hash|
        new_rules_lookup[rule_hash[:rule_type]] = rule_hash

        if existing_rules_lookup.key?(rule_hash[:rule_type])
          rule = existing_rules_lookup[rule_hash[:rule_type]]
          rule.parameters = apply_default_parameters ? apply_default_parameters(rule[:rule_type], rule_hash[:parameters] || {}) : rule_hash[:parameters]
          rule.parameters = rule.recognized_parameters if remove_unknown_parameters

          next unless rule.changed?
          next if rule.changed_attributes.keys == ["parameters"] && Hashdiff.diff(rule.attributes["parameters"] || {}, rule.changed_attributes["parameters"] || {}).empty?

          rule.updated_by_id = actor_id || GitHub.context[:actor_id]

          raise RuleEngine::IRuleset::RuleValidationError.new(rule.errors) unless rule.save

          rules_updated << rule
          next
        end

        rule = self.rule_configurations.build(
          rule_type: rule_hash[:rule_type],
          parameters: apply_default_parameters ? apply_default_parameters(rule_hash[:rule_type], rule_hash[:parameters] || {}) : rule_hash[:parameters],
          created_by_id: actor_id || GitHub.context[:actor_id]
        )

        rule.parameters = rule.recognized_parameters if remove_unknown_parameters

        raise RuleEngine::IRuleset::RuleValidationError.new(rule.errors) unless rule.save

        rules_added << rule
      end

      existing_rules_lookup.each do |key, rule|
        next if new_rules_lookup.key?(key)

        self.rule_configurations.destroy(rule)

        rules_deleted << rule
      end

      was_changed = rules_added.any? || rules_updated.any? || rules_deleted.any?
      if persisted? && was_changed
        touch_later
      end
      was_changed
    end

    sig { override.returns(RulesetDefinitions::RulesetDefinition) }
    def definition
      @definition ||= T.let(RulesetDefinitions::RulesetDefinition.factory(source, source_type, target), T.nilable(RulesetDefinitions::RulesetDefinition))
    end

    sig { override.params(rule_type: String, parameters: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
    def apply_default_parameters(rule_type, parameters)
      parameters = parameters.deep_stringify_keys
      impl = RuleEngine::Evaluator.rule_impl_for_rule_type(rule_type)
      return parameters if impl.nil?

      impl.parameter_schema.apply_defaults_for_source(source, parameters)
      parameters
    end

    sig do
      override.params(
        targetable: Targeting::Targetable,
        target_object: RuleEngine::Conditions::ConditionTarget::TargetObject
      ).returns(T::Boolean)
    end
    def satisfies_conditions?(targetable, target_object)
      trace_time("ruleset_satisfies_conditions", tags: ["target:#{target}", "enforcement:#{enforcement}", "source_type:#{source_type}"]) do
        return false if conditions.none? || conditions.none? { |condition| condition.target_object == target_object }
        return false unless definition.can_evaluate_targetable?(targetable)

        condition = conditions.find { |condition| condition.target_object == target_object }
        return false unless condition

        RuleEngine::Conditions::Evaluator.evaluate([targetable], { condition.target => condition.parameters }).any?
      end
    end

    sig do
      override.params(targetable: Targeting::Targetable)
      .returns(T::Boolean)
    end
    def should_evaluate?(targetable)
      trace_time("ruleset_should_evaluate", tags: ["target:#{target}", "enforcement:#{enforcement}", "source_type:#{source_type}"]) do
        bulk_filter_targetable([targetable]) == [targetable]
      end
    end

    sig do
      override.type_parameters(:T)
        .params(targetables: T::Enumerable[T.all(Targeting::Targetable, T.type_parameter(:T))])
        .returns(T::Array[T.all(Targeting::Targetable, T.type_parameter(:T))])
    end
    def bulk_filter_targetable(targetables)
      trace_time("bulk_filter_targetable", tags: ["target:#{target}", "enforcement:#{enforcement}", "source_type:#{source_type}"]) do
        return [] if disabled?
        return [] if evaluate? && !source.plan_supports?(:enterprise_rulesets)
        return [] unless definition.is_valid?

        # If the ruleset does not have all required conditions, skip evaluation
        actual_condition_targets = conditions.map { |condition| T.must(condition.target_object) }.sort
        required_condition_targets = definition.required_condition_targets.sort
        return [] unless actual_condition_targets & required_condition_targets == required_condition_targets

        # Only consider valid targets
        relevant_targetables = targetables.to_h { [definition.redirect_condition_targetable(_1), _1] }
          .filter { |redirected, _| definition.can_evaluate_targetable?(redirected) }

        parameters_by_condition = conditions.to_h { |condition| [condition.target, condition.parameters] }
        matching_targetables = RuleEngine::Conditions::Evaluator.evaluate(relevant_targetables.keys, parameters_by_condition)

        matching_targetables.map { |targetable| relevant_targetables[targetable] }.compact
      end
    end

    sig { override.returns(T::Array[RuleEngine::Conditions::ConditionTarget::TargetObject]) }
    def missing_condition_targets
      actual_condition_targets = conditions.map { |condition| condition.target_object }.sort
      required_condition_targets = definition.required_condition_targets.sort

      required_condition_targets - actual_condition_targets
    end

    sig { override.params(allow_upsell: T::Boolean).returns(T::Array[String]) }
    def available_rule_types(allow_upsell: false)
      @available_rule_types ||= T.let({}, T.nilable(T::Hash[T.untyped, T.untyped]))
      @available_rule_types[allow_upsell] ||= RuleEngine::Evaluator::REGISTERED_RULES.filter_map do |_, rule|
        next unless rule.is_user_configurable?(source) &&
          rule.is_feature_enabled?(source) &&
          rule.is_supported_by_source_type?(source) &&
          rule.is_supported_by_plan?(source, allow_upsell:) &&
          rule.is_supported_by_target?(target)
        rule.rule_name
      end
    end

    batch_method(:latest_history_id, T.nilable(Integer)) do |rulesets|
      histories_by_ruleset = ActionsRulesetHistory.where(actions_ruleset_id: rulesets.map(&:id))
        .pluck(:id, :actions_ruleset_id, :created_at)
        .reduce({}) do |acc, (id, actions_ruleset_id, created_at)|
          acc[actions_ruleset_id] ||= []
          acc[actions_ruleset_id] << { id: id, created_at: created_at }
          acc
        end

      latest_histories = histories_by_ruleset.to_h do |actions_ruleset_id, histories|
        [actions_ruleset_id, histories.max_by { |history| history[:created_at] }[:id]]
      end

      rulesets.index_with { |ruleset| latest_histories[ruleset.id] }
    end

    sig { void }
    def append_history
      updated_by_id = GitHub.context[:actor_id] || User.ghost

      self.rule_configurations.reload
      self.conditions.reload

      state = serialize

      self.histories.create(
        state:,
        updated_by_id:,
      )
    end

    sig { returns(String) }
    def serialize
      serialized = self.as_json(
        only: [
          :id,
          :name,
          :source_id,
          :source_type,
          :enforcement,
          :target,
        ], include: [
          rule_configurations: {
            only: [
              :id,
              :parameters,
              :rule_type,
            ],
            root: false,
          },
          conditions: {
            only: [
              :id,
              :parameters,
              :target,
              :condition_type,
            ],
            root: false,
          },
        ], root: false
      )

      serialized.to_json
    end

    sig { override.returns(RuleEngine::RuleProviders::RulesetRuleProvider) }
    def rule_provider
      T.cast(RuleEngine::Evaluator::RULE_PROVIDERS.find { |rp| rp.identifier == "ref_ruleset" }, RuleEngine::RuleProviders::RulesetRuleProvider)
    end

    sig { override.returns(T::Enumerable[T.untyped]) }
    def bypass_actors
      []
    end

    private

    def ensure_rules_valid
      return unless rule_configurations.any? { |rule| rule.errors.any? }

      errors.add(:base, "Rules are invalid")
    end

    def ensure_conditions_valid
      return unless conditions.any? { |condition| condition.errors.any? }

      errors.add(:base, "Conditions are invalid")
    end

    def ensure_valid_plan
      unless !evaluate? || definition.supports_evaluate_mode?
        errors.add(:enforcement, "evaluate option is not supported on this plan. Please upgrade to Enterprise to enable it.")
      end
    end

    def ensure_ruleset_limit_not_exceeded
      return unless source.present?

      if self.class.limit_reached?(source)
        errors.add(:base, "Ruleset limit has been reached")
      end
    end

    def ensure_valid_target
      unless definition.ruleset_feature_enabled?
        errors.add(:target, "not supported")
      end
    end

    def ensure_valid_source
      definition.validation_errors.each do |message|
        errors.add(:source, message)
      end
    end
  end
end
