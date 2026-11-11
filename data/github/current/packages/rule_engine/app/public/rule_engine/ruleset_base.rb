# typed: strict
# frozen_string_literal: true

module RuleEngine
  module RulesetBase
    extend T::Helpers
    extend ActiveSupport::Concern
    include IRuleset
    include GitHub::BatchMethod

    requires_ancestor { ActiveRecord::Base }

    abstract!

    ENFORCEMENT_DISPLAY_VALUES = T.let({
      disabled: :disabled,
      enabled: :active,
      evaluate: :evaluate
    }.with_indifferent_access.freeze, T::Hash[T.any(String, Symbol), Symbol])

    included do
      T.bind(self, T.all(ClassMethods, T.class_of(ApplicationRecord::Base)))

      belongs_to :source, polymorphic: true

      has_many :conditions, class_name: impl_payload.rule_condition_class
      destroy_dependents_in_background :conditions

      has_many :rule_configurations, class_name: impl_payload.rule_configuration_class, inverse_of: impl_payload.ruleset_association_name.to_sym
      destroy_dependents_in_background :rule_configurations

      if impl_payload.ruleset_bypass_actor_class.present?
        has_many :bypass_actors, class_name: impl_payload.ruleset_bypass_actor_class, autosave: true
        destroy_dependents_in_background :bypass_actors
      end

      has_many :histories, -> { order("created_at DESC") }, class_name: impl_payload.ruleset_history_class
      destroy_dependents_in_background :histories

      validate :ensure_rules_valid
      validate :ensure_conditions_valid
      validate :ensure_valid_plan
      validate :ensure_valid_target
      validate :ensure_valid_source
      validate :ensure_ruleset_limit_not_exceeded, on: :create

      batch_method(:latest_history_id, T.nilable(Integer)) do |rulesets|
        T.bind(self, T.all(ClassMethods, T.class_of(ApplicationRecord::Base)))

        ruleset_id_column = "#{impl_payload.ruleset_association_name}_id".to_sym
        history_class = impl_payload.ruleset_history_class.constantize

        ruleset_ids = rulesets.map(&:id)
        vexi_actor_prefix = "#{impl_payload.class.name}:"
        use_perf_fix = ruleset_ids.any? do |ruleset_id|
          FeatureFlag.vexi.enabled?(:ruleset_latest_history_id_perf_fix, "#{vexi_actor_prefix}#{ruleset_id}", default: false)
        end

        latest_histories = if use_perf_fix
          history_table = history_class.table_name
          latest_created_at_per_ruleset = history_class
            .where(ruleset_id_column => ruleset_ids)
            .select("#{ruleset_id_column}, MAX(created_at) AS max_created_at")
            .group(ruleset_id_column)

          history_class
            .joins("INNER JOIN (#{latest_created_at_per_ruleset.to_sql}) latest_created_at_by_ruleset ON latest_created_at_by_ruleset.#{ruleset_id_column} = #{history_table}.#{ruleset_id_column} AND latest_created_at_by_ruleset.max_created_at = #{history_table}.created_at")
            .where(ruleset_id_column => ruleset_ids)
            .group("#{history_table}.#{ruleset_id_column}")
            .maximum("#{history_table}.id")
        else
          histories_by_ruleset = history_class.where(ruleset_id_column => ruleset_ids)
           .pluck(:id, ruleset_id_column, :created_at)
           .reduce({}) do |acc, (id, ruleset_id, created_at)|
            acc[ruleset_id] ||= []
            acc[ruleset_id] << { id: id, created_at: created_at }
            acc
          end

          histories_by_ruleset.to_h do |ruleset_id, histories|
            [ruleset_id, histories.max_by { |history| history[:created_at] }[:id]]
          end
        end

        rulesets.index_with { |ruleset| latest_histories[ruleset.id] }
      end
    end

    sig { abstract.returns(T.untyped) }
    def source; end

    sig { abstract.returns(T.all(ActiveRecord::Associations::CollectionProxy, T::Enumerable[RuleConditionBase])) }
    def conditions; end

    sig { abstract.returns(T.all(ActiveRecord::Associations::CollectionProxy, T::Enumerable[RuleConfigurationBase])) }
    def rule_configurations; end

    #sig { abstract.returns(T.all(ActiveRecord::Associations::CollectionProxy, T::Enumerable[RulesetBypassActorBase])) }
    #def bypass_actors; end

    sig { abstract.returns(T.all(ActiveRecord::Associations::CollectionProxy, T::Enumerable[RulesetHistoryBase])) }
    def histories; end

    sig { returns(T.nilable(Integer)) }
    def latest_history_id; end

    # TODO: Ruleset operations should all go through a domain instead of writing directly to the ActiveRecord models
    sig { abstract.params(name: String).returns(String) }
    def name=(name); end

    sig { abstract.params(target: String).returns(String) }
    def target=(target); end

    sig { abstract.params(source: T.untyped).returns(T.untyped) }
    def source=(source); end

    sig { abstract.params(enforcement: String).returns(String) }
    def enforcement=(enforcement); end

    sig { override.params(viewing_source: T.untyped).returns(String) }
    def display_source_type(viewing_source: nil)
      definition.display_type(viewing_source:)
    end

    sig { returns(String) }
    def display_source_name
      definition.display_source_name
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
          next if unchanged_parameter_update?(rule)

          rule.updated_by_id = actor_id || GitHub.context[:actor_id]

          raise IRuleset::RuleValidationError.new(rule.errors) unless rule.save

          rules_updated << rule
          next
        end

        rule = self.rule_configurations.build(
          rule_type: rule_hash[:rule_type],
          parameters: apply_default_parameters ? apply_default_parameters(rule_hash[:rule_type], rule_hash[:parameters] || {}) : rule_hash[:parameters],
          created_by_id: actor_id || GitHub.context[:actor_id]
        )

        rule.parameters = rule.recognized_parameters if remove_unknown_parameters

        raise IRuleset::RuleValidationError.new(rule.errors) unless rule.save

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
          next if condition.changed_attributes.keys == ["parameters"] && (condition.attributes["parameters"] || {}) == (condition.changed_attributes["parameters"] || {})

          raise RuleEngine::IRuleset::ConditionValidationError.new(condition, condition.parameter_errors) if !condition.valid? && condition.parameter_errors.any?

          condition.save!

          conditions_updated << condition
          next
        end

        condition = self.conditions.build(
          target: condition_hash[:target],
          parameters: condition_hash[:parameters] || {},
        )

        raise RuleEngine::IRuleset::ConditionValidationError.new(condition, condition.parameter_errors) if !condition.valid? && condition.parameter_errors.any?

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

    sig { overridable.params(new_bypass_actors: T::Array[{ actor_type: String, bypass_mode: T.nilable(T.any(Symbol, Integer)) }]).returns(T::Boolean) }
    def upsert_bypass_actors(new_bypass_actors)
      false # TODO: Support bypass actors for all ruleset types
    end

    sig { override.returns(RulesetDefinitions::RulesetDefinition) }
    def definition
      @definition ||= T.let(RulesetDefinitions::RulesetDefinition.factory(source, source_type, target), T.nilable(RulesetDefinitions::RulesetDefinition))
    end

    sig { params(user: User).returns(T::Boolean) }
    def can_user_edit?(user)
      cache = @can_user_edit_cache ||= T.let({}, T.nilable(T::Hash[Integer, T::Boolean]))
      cache.fetch(user.id) { cache[user.id] = definition.can_user_edit?(user) }
    end

    sig { override.params(rule_type: String, parameters: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
    def apply_default_parameters(rule_type, parameters)
      parameters = parameters.deep_stringify_keys
      impl = domain.registry.rule_impl_for_rule_type(rule_type)
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

      rules = domain.registry.rule_implementations
      @available_rule_types[allow_upsell] ||= rules.filter_map do |_, rule|
        next unless rule.is_user_configurable?(source) &&
          rule.is_feature_enabled?(source) &&
          rule.is_supported_by_source_type?(source) &&
          rule.is_supported_by_plan?(source, allow_upsell:) &&
          rule.is_supported_by_target?(target)
        rule.rule_name
      end
    end

    sig { void }
    def append_history
      updated_by_id = GitHub.context[:actor_id] || User.ghost

      self.rule_configurations.reload
      self.conditions.reload
      T.unsafe(self.bypass_actors).reload if impl_payload.ruleset_bypass_actor_class.present?

      state = serialize

      self.histories.create(
        state:,
        updated_by_id:,
      )
    end

    DEFAULT_SERIALIZATION_FIELDS = [
      :id,
      :name,
      :source_id,
      :source_type,
      :enforcement,
      :target
    ].freeze

    DEFAULT_SERAILIZATION_ASSOCIATIONS = T.let({
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
    }, T::Hash[Symbol, T.untyped])

    sig { abstract.returns(String) }
    def serialize; end

    private

    sig { returns(RulesetImplementationPayload) }
    def impl_payload
      T.cast(self.class, ClassMethods).impl_payload
    end

    sig { void }
    def ensure_valid_plan
      unless !evaluate? || definition.supports_evaluate_mode?
        errors.add(:enforcement, "evaluate option is not supported on this plan. Please upgrade to Enterprise to enable it.")
      end
    end

    sig { params(rule: RuleEngine::RuleConfigurationBase).returns(T::Boolean) }
    def unchanged_parameter_update?(rule)
      return false unless rule.changed_attributes.keys == ["parameters"]

      old_parameters = (rule.changed_attributes["parameters"] || {}).deep_stringify_keys
      new_parameters = (rule.attributes["parameters"] || {}).deep_stringify_keys

      return true if new_parameters == old_parameters

      impl = rule.evaluator
      ruleset_source = source
      return false if impl.nil? || ruleset_source.nil?

      visible_schema = impl.parameter_schema_for_source(ruleset_source)
      visible_old = rule.visible_parameters_for_schema(old_parameters, visible_schema.fields)
      visible_new = rule.visible_parameters_for_schema(new_parameters, visible_schema.fields)

      visible_new == visible_old
    end

    sig { void }
    def ensure_valid_target
      unless definition.ruleset_feature_enabled?
        errors.add(:target, "not supported")
      end
    end

    sig { void }
    def ensure_valid_source
      definition.validation_errors.each do |message|
        errors.add(:source, message)
      end
    end

    sig { void }
    def ensure_rules_valid
      rule_configurations.each do |rule|
        unless rule.valid?
          errors.add(:rule_configurations, "contain invalid rule with type #{rule.rule_type}: #{rule.errors.full_messages.join(", ")}")
        end
      end
    end

    sig { void }
    def ensure_conditions_valid
      conditions.each do |condition|
        unless condition.valid?
          errors.add(:conditions, "contain invalid condition with target #{condition.target}: #{condition.errors.full_messages.join(", ")}")
        end
      end
    end

    sig { void }
    def ensure_ruleset_limit_not_exceeded
      return unless source.present?

      if domain.limit_reached?(source)
        errors.add(:base, "The ruleset limit of #{domain.ruleset_limit(source)} has been reached.")
      end
    end

    module ClassMethods
      include Kernel

      sig { returns(RulesetImplementationPayload) }
      def impl_payload
        raise NotImplementedError, "Subclass must implement class method `impl_payload`"
      end
    end
    mixes_in_class_methods(ClassMethods)
  end
end
