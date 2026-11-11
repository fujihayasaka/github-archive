# typed: strict
# frozen_string_literal: true

module RuleEngine
  module DomainAccessorBase
    extend T::Helpers
    extend T::Generic
    extend ActiveSupport::Concern
    include Scientist
    include GitHub::Memoizer

    requires_ancestor { GH::Domain::Base }

    RuleSource = type_member { { upper: T.all(ActiveRecord::Base, GitHub::VexiActor) } }

    RulesetClassType = T.type_alias do
      T.all(
        IRuleset::ClassMethods,
        T.class_of(ActiveRecord::Base),
        T::Class[T.all(ActiveRecord::Base, RulesetBase)],
      )
    end

    included do
      T.bind(self, T.class_of(GH::Domain::Base))

      # WrapPreloads breaks methods that return more than one type. Specifically, `inherited_sources` breaks a lot of
      # downstream calls. There is no way to disable WrapPreloads for specific methods, so we only apply it to `ruleset_class`
      # which will never use it.
      decorate_with GH::Decorator::WrapPreloads, only: [:ruleset_class]
    end

    abstract!

    # Abstract: Returns the ActiveRecord class for rulesets in this domain. Must be implemented by the including class.
    sig { abstract.returns(RulesetClassType) }
    def ruleset_class; end

    # Abstract: Returns a hash mapping RuleSource classes to their priority (lower number = higher priority). Must be implemented by the including class.
    sig { abstract.returns(T::Hash[T::Class[RuleSource], Integer]) }
    def source_priority; end

    # Abstract: Returns an array of sources from which the given source can inherit rulesets. Must be implemented by the including class.
    #
    # source can be anything, not just a RuleSource. This allows objects to inherit rulesets from other sources without allowing
    # them to define rulesets themselves.
    sig { abstract.params(source: T.untyped, target: String).returns(T::Array[RuleSource]) }
    def inherited_sources(source, target); end

    # Abstract: Returns the maximum number of rulesets allowed for the given source. Must be implemented by the including class.
    sig { abstract.params(source: RuleSource).returns(Integer) }
    def ruleset_limit(source); end

    sig { returns(RuleEngine::GenericEvaluator) }
    memoize def evaluator
      RuleEngine::GenericEvaluator.new(registry)
    end

    # Loads the rulesets for the given source, optionally including inherited rulesets from other sources.
    sig { params(source: RuleSource, targets: T::Array[String], include_inherited: T::Boolean).returns(T::Array[IRuleset]) }
    def load_rulesets(source, targets:, include_inherited: true)
      raise ArgumentError, "targets cannot be empty" if targets.size == 0

      all_sources = Set.new([source])
      ruleset_query = if include_inherited
        scopes = targets.filter_map do |target|
          sources = [source].concat(inherited_sources(source, target))
          next if sources.empty?
          all_sources.merge(sources)
          ruleset_class.where(source: sources, target: target)
        end
        scopes.reduce(&:or)
      else
        ruleset_class.where(source:, target: targets)
      end

      return [] if ruleset_query.nil?
      loaded_rulesets = ruleset_query.order(source_type: :desc).includes(:rule_configurations, :conditions)
      GitHub::PrefillAssociations.prefill_associations(loaded_rulesets, :source, available_records: all_sources.to_a)

      rulesets = loaded_rulesets.filter do |ruleset|
        ruleset.definition.applies_to_source?(ruleset, source)
      end

      rulesets.sort do |a, b|
        if a.source == b.source
          a.name <=> b.name || 0
        else
          source_priority.fetch(a.source.class, 10) <=> source_priority.fetch(b.source.class, 10)
        end
      end
    end

    # You probably want to use `load_rulesets` instead of this method for most cases
    #
    # Bulk loads rulesets for the given sources and targets
    # This does not load inherited rulesets from the parents of the provided sources
    sig { params(sources: T::Array[RuleSource], targets: T::Array[String], preload_associations: T::Boolean).returns(T::Array[IRuleset]) }
    def load_rulesets_for_sources(sources, targets:, preload_associations: true)
      rulesets = ruleset_class.where(source: sources, target: targets).order(source_type: :desc)
      rulesets = rulesets.includes(:rule_configurations, :conditions) if preload_associations

      GitHub::PrefillAssociations.prefill_associations(rulesets, :source, available_records: sources)
      rulesets.to_a
    end

    # Check whether a ruleset name is already taken for this source.
    sig { params(source: RuleSource, name: String, exclude_id: T.nilable(Integer)).returns(T::Boolean) }
    def name_exists?(source, name, exclude_id: nil)
      query = ruleset_class.where(source: source, name: name)
      query = query.where.not(id: exclude_id) unless exclude_id.nil?
      query.exists?
    end

    sig { params(source: RuleSource, ruleset_id: Integer, targets: T::Array[String], include_inherited: T::Boolean).returns(T.nilable(IRuleset)) }
    def ruleset_from_id(source, ruleset_id, targets:, include_inherited: false)
      rulesets = load_rulesets(source, include_inherited: include_inherited, targets: targets)
      rulesets.find { |ruleset| ruleset.id == ruleset_id }
    end

    sig { params(source: RuleSource, ruleset_ids: T::Array[Integer], targets: T::Array[String], include_inherited: T::Boolean).returns(T::Array[RuleEngine::IRuleset]) }
    def rulesets_from_ids(source, ruleset_ids, targets:, include_inherited: false)
      rulesets = load_rulesets(source, include_inherited: include_inherited, targets: targets)
      ruleset_ids_set = ruleset_ids.to_set
      rulesets.select { |ruleset| (id = ruleset.id) && ruleset_ids_set.include?(id) }
    end

    sig { params(source: RuleSource).returns(T::Boolean) }
    def limit_reached?(source)
      ruleset_class.where(source: source).count >= ruleset_limit(source)
    end

    sig { params(source: RuleSource, target: String, enforcement: T.nilable(String)).returns(T.nilable(IRuleset)) }
    def new_ruleset_with_defaults(source, target, enforcement:)
      return nil unless ruleset_class.targets.include?(target)

      ruleset = ruleset_class.new
      ruleset.target = target
      ruleset.source = source
      ruleset.enforcement = enforcement.present? && ruleset_class.enforcements.include?(enforcement) ? enforcement : "disabled"

      RulesEngine::ReactPayload.available_rule_schemas(ruleset).each do |rule_schema|
        defaults = registry.default_rules_for_target(target)
        next if defaults.nil? || defaults.exclude?(rule_schema[:type])

        ruleset.rule_configurations.new(
          rule_type: rule_schema[:type],
          parameters: ruleset.apply_default_parameters(rule_schema[:type], {})
        )
      end

      ruleset
    end

    sig { params(source: RuleSource, current_ruleset: RulesetBase, ruleset_json: T::Hash[String, T.untyped], current_user: User).returns([T.nilable(String), T::Hash[Symbol, T::Hash[T.untyped, T.untyped]]]) }
    def update_ruleset_from_json(source, current_ruleset, ruleset_json, current_user)
      changes = current_ruleset.name != ruleset_json["name"] ||
                current_ruleset.target != ruleset_json["target"] ||
                current_ruleset.enforcement != ruleset_json["enforcement"]

      current_ruleset.name = ruleset_json["name"]
      current_ruleset.target = ruleset_json["target"]
      current_ruleset.enforcement = ruleset_json["enforcement"]

      save_changes(source, current_ruleset, ruleset_json, current_user, changes:)
    end

    sig { params(source: RuleSource, ruleset_target: String).returns(T::Array[String]) }
    def supported_condition_target_objects(source, ruleset_target)
      definition = RulesetDefinitions::RulesetDefinition.factory(source, nil, ruleset_target)
      definition.required_condition_targets
    end

    sig do
      params(
        source: RuleSource,
        ruleset: RulesetBase,
        ruleset_json: T::Hash[String, T.untyped],
        current_user: User,
        changes: T::Boolean,
      ).returns([T.nilable(String), T::Hash[Symbol, T::Hash[T.untyped, T.untyped]]])
    end
    def save_changes(source, ruleset, ruleset_json, current_user, changes: true)
      error_message = T.let(nil, T.nilable(String))
      detailed_errors = { general: Hash.new { |h, k| h[k] = [] }, rules: {}, bypass_actors: {}, conditions: Hash.new { |h, k| h[k] = [] } }

      rules_to_save = filter_and_translate_rules_for_save(ruleset_json["rules"])
      bypass_actors_to_save = filter_and_translate_bypass_actors_for_save(ruleset_json["bypassActors"])
      conditions_to_save = translate_conditions_for_save(ruleset_json["conditions"])
      remove_unknown_parameters = ruleset.source.feature_enabled_for_source?(:ruleset_ui_remove_unknown_parameters)

      begin
        ruleset_class.transaction do
          ruleset.target = ruleset_json["target"] || "branch"

          conditions_changed = ruleset.upsert_conditions(T.unsafe(conditions_to_save))
          bypass_actors_changed = ruleset.upsert_bypass_actors(T.unsafe(bypass_actors_to_save))
          rules_changed = ruleset.upsert_rules(T.unsafe(rules_to_save), apply_default_parameters: true, remove_unknown_parameters:, actor_id: current_user.id)

          changed = ruleset.changed? || conditions_changed || bypass_actors_changed || rules_changed

          if !changed
            error_message = "No changes have been made"
            next
          end

          ruleset.save!
        end
      rescue RuleEngine::IRuleset::ConditionValidationError => e
        error_message = e.parse_error_messages.to_sentence

        detailed_errors[:conditions][e.parameter_instance.target_object] << {
          field: e.parameter_instance.target,
          message: error_message
        }
      rescue RuleEngine::IRuleset::RuleValidationError => e
        failed_rules = e.errors.map { |error| error.base.rule_type.humanize }

        e.errors.each do |error|
          detailed_errors[:rules][error.base.rule_type] = error.base.parameter_errors
        end

        error_message = "Invalid rules: \'#{failed_rules.uniq.join("\', \'")}\'"
      rescue ActiveRecord::RecordInvalid => e
        error_message = e.record.errors.full_messages.to_sentence
        e.record.errors.each do |error|
          detailed_errors[:general][error.attribute] << {
              error_code: error.type,
              message: error.full_message,
              field: error.attribute
            }
        end
      rescue RepositoryRulesetBypassActor::ValidationError => e
        failed_rules = e.errors.map { |error| error.message }
        error_message = failed_rules.uniq.join("\', \'")
      end

      [error_message, detailed_errors]
    end

    sig { returns(Registry) }
    def registry
      T.cast(self.class, ClassMethods).registry
    end

    private

    sig { params(rules: T.nilable(T::Array[T::Hash[String, T.untyped]])).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def filter_and_translate_rules_for_save(rules)
      rules_to_save = []

      rules&.each do |raw_rule|
        type = group_raw_rule(raw_rule)

        next if type == :delete

        raw_rule["id"] = nil if raw_rule["id"].blank?
        raw_rule["rule_type"] = raw_rule["ruleType"] if raw_rule["ruleType"].present?
        raw_rule.except!("_id", "_dirty", "_enabled")

        rules_to_save << raw_rule.deep_symbolize_keys
      end

      rules_to_save
    end

    sig { params(bypass_actors: T.nilable(T::Array[T::Hash[String, T.untyped]])).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def filter_and_translate_bypass_actors_for_save(bypass_actors)
      bypass_actors_to_save = []

      bypass_actors&.each do |raw_bypass_actor|
        type = group_raw_rule(raw_bypass_actor)

        next if type == :delete

        raw_bypass_actor.delete("id")
        raw_bypass_actor.except!("_id", "_dirty", "_enabled")

        bypass_actors_to_save << raw_bypass_actor.deep_transform_keys { |key| key.to_s.underscore.to_sym }
      end

      bypass_actors_to_save
    end

    sig { params(conditions: T.nilable(T::Array[T::Hash[String, T.untyped]])).returns(T::Array[T::Hash[String, T.untyped]]) }
    def translate_conditions_for_save(conditions)
      conditions&.map do |condition|
        condition.except!("_dirty")
      end || []
    end

    # Take a rule request object (hash) and return a Symbol to group by
    # (:create, :update, :delete) or nil if it doesn't need to be saved
    sig { params(raw_rule: T.untyped).returns(T.nilable(Symbol)) }
    def group_raw_rule(raw_rule)
      # skip rules that don't have an ID and are not enabled, _or_ are not marked 'dirty' (needs to be saved)
      if (raw_rule["id"].blank? && !raw_rule["_enabled"]) || !raw_rule["_dirty"]
        return nil
      end

      # Group rules by update and delete based on the enabled flag
      if (raw_rule["id"].blank?) && raw_rule["_enabled"]
        :create
      elsif raw_rule["_enabled"]
        :update
      # If a rule is found and not enabled, delete it
      else
        :delete
      end
    end

    module ClassMethods
      include Kernel
      include GitHub::Memoizer

      sig { returns(Registry) }
      memoize def registry
        Registry.new
      end

      sig { params(rule_impl: BaseRule).void }
      def register_rule_implementation(rule_impl)
        registry.register_rule_implementation(rule_impl)
      end

      sig { params(parent_rule_name: String, companion_impl: BaseRule).void }
      def register_companion_rule(parent_rule_name, companion_impl)
        registry.register_companion_rule(parent_rule_name, companion_impl)
      end

      sig { params(provider: RuleProvider).void }
      def register_rule_provider(provider)
        registry.register_rule_provider(provider)
      end

      sig { params(target: String, rule_names: T::Array[String]).void }
      def register_default_rules(target, rule_names)
        registry.register_default_rules(target, rule_names)
      end
    end
    mixes_in_class_methods(ClassMethods)
  end
end
