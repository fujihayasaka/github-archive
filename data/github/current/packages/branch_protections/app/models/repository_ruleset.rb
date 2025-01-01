# typed: true
# frozen_string_literal: true

require "hashdiff"

class RepositoryRuleset < ApplicationRecord::Repositories
  include Instrumentation::Model
  include GitHub::Memoizer
  include GitHub::BatchMethod
  include RuleEngine::Timing
  extend RuleEngine::Timing

  RULESET_LIMIT = 75
  RULESET_SECOND_LIMIT = 200

  after_commit :append_history, on: [:create, :update]

  validates_uniqueness_of :name, scope: [:source], case_sensitive: false, message: "must be unique"
  before_validation :strip_whitespace
  validates_presence_of :name, message: "cannot be empty"
  validates_presence_of :source

  enum :target, { branch: 0, tag: 1, push: 2, repository: 3 }, prefix: :targets

  belongs_to :source, polymorphic: true
  destroy_in_background_with :source, polymorphic_class_name: "Repository"
  has_many :conditions, class_name: "RepositoryRuleCondition"
  destroy_dependents_in_background :conditions

  has_many :rule_configurations, class_name: "RepositoryRuleConfiguration", inverse_of: :repository_ruleset
  destroy_dependents_in_background :rule_configurations

  has_many :bypass_actors, class_name: "RepositoryRulesetBypassActor", autosave: true
  destroy_dependents_in_background :bypass_actors

  has_many :histories, -> { order("created_at DESC") }, class_name: "RepositoryRulesetHistory"
  destroy_dependents_in_background :histories

  AUDITABLE_FIELDS = %i[enforcement name].freeze

  validate :bypass_actors_valid
  validate :ensure_valid_plan
  validate :ensure_valid_target
  validate :ensure_ruleset_limit_not_exceeded, on: :create
  validate :ensure_valid_source

  ENFORCEMENT_DISPLAY_VALUES = {
    disabled: :disabled,
    enabled: :active,
    evaluate: :evaluate
  }.with_indifferent_access.freeze
  enum :enforcement, { disabled: 0, enabled: 1, evaluate: 2 }

  # Primarily used in the graphql context
  # Set the node from which we are requesting rulesets to properly determine
  # if the viewer has access to rulesets within this context
  sig { returns(T.nilable(RuleEngine::Types::RuleSource)) }
  attr_accessor :source_node

  # Boolean value set by `load_for` that indicates whether or not the ruleset
  # was inherited from the network
  sig { returns(T.nilable(T::Boolean)) }
  attr_accessor :inherited_from_network

  attr_accessor :bypass_actors_added
  attr_accessor :bypass_actors_updated
  attr_accessor :bypass_actors_deleted

  after_create_commit :instrument_create
  after_update_commit :instrument_update
  after_destroy_commit :instrument_destroy

  before_destroy :generate_deleted_webhook_payload
  after_destroy_commit :queue_webhook_delivery
  after_update_commit :queue_update_webhook_delivery

  after_commit :reconcile_merge_queues, on: [:create, :update, :destroy]

  # definition encapsulates the specific behavior of rules based on their target type
  # push rules have different behavior than branch or tag rules
  sig { returns(RulesetDefinitions::RulesetDefinition) }
  def definition
    @definition ||= RulesetDefinitions::RulesetDefinition.factory(source, source_type, target)
  end

  def strip_whitespace
    self[:name] = self[:name]&.strip
  end

  # The "User" source type is actually an Organization
  def display_source_type
    definition.display_type
  end

  def display_source_name
    definition.display_source_name
  end

  def self.ruleset_limit_count(source)
    if source.ruleset_second_limit_enabled?
      RULESET_SECOND_LIMIT
    else
      RULESET_LIMIT
    end
  end

  def self.limit_reached?(source)
    source.rulesets.count >= ruleset_limit_count(source)
  end

  # copy any active repo rules to the target repo, excluding any bypasses
  def self.copy_rules(source_repo, target_repo, targets, validate: true)
    source_rulesets = []
    target_rulesets = []
    # exit early if either repo is nil
    return [source_rulesets, target_rulesets] unless source_repo && target_repo

    if ((source_repo.id != target_repo.id) &&
      source_repo.plan_supports?(:enterprise_rulesets) &&
      target_repo.owner&.plan_supports?(:enterprise_rulesets))

      source_rulesets = RepositoryRuleset.load_for(source: source_repo, include_parents: false, targets: targets).select(&:enabled?)

      source_rulesets.each do |source_ruleset|
        target_ruleset = source_ruleset.dup
        target_ruleset.source = target_repo
        target_ruleset.save!(validate: validate)
        target_rulesets << target_ruleset

        source_ruleset.rule_configurations.each do |source_config|
          target_config = source_config.dup
          target_config.repository_ruleset_id = target_ruleset.id
          target_config.save!
        end

        # we are only copying repo-level rulesets, so we should be OK with copying all conditions
        source_ruleset.conditions.each do |source_condition|
          target_condition = source_condition.dup
          target_condition.repository_ruleset_id = target_ruleset.id
          target_condition.save!
        end
      end
    end
    [source_rulesets, target_rulesets]
  end

  # Loads rulesets for the given source
  # include_parents: if true, also loads rulesets from the parent source
  # targets: specifies which rulesets types to load. If nil, all rulesets are loaded.
  # check_conditions_on_parent_rulesets: if true, run conditions to ensure inherited rulesets apply to the source
  #   `false` during evaluation to ensure conditions are not run twice
  sig do
    params(
      source: RuleEngine::Types::RuleSource,
      include_parents: T::Boolean,
      targets: T.nilable(T::Array[String]),
      check_conditions_on_parent_rulesets: T::Boolean
    ).returns(T::Array[RepositoryRuleset])
  end
  def self.load_for(source:, include_parents: false, targets: nil, check_conditions_on_parent_rulesets: true)
    trace_time("ruleset.load_for", tags: ["source_type:#{source.class.name}", "include_parents:#{include_parents}", "targets:#{targets}"]) do
      sources = [source]

      if include_parents
        sources |= source.inherited_sources
      end

      # Organizations need to appear before Repositories
      rulesets = self.where(source: sources).order(source_type: :desc).includes(:rule_configurations, :conditions)

      GitHub::PrefillAssociations.prefill_associations(rulesets, :source, available_records: sources)

      rulesets = rulesets.filter do |ruleset|
        ruleset.definition.applies_to_targets?(targets) &&
        (!check_conditions_on_parent_rulesets || ruleset.definition.applies_to_source?(ruleset, source))
      end

      rulesets.each { |ruleset| ruleset.inherited_from_network = false }

      if include_parents
        # If the source is a repo and target is a push, we need to include push rulesets from the network root
        rulesets |= RulesetDefinitions::RepositoryPush.network_rulesets(source: source, targets: targets)
      end

      rulesets
    end
  end

  sig do
    params(targetable: RuleEngine::Conditions::Targetable)
    .returns(T::Boolean)
  end
  def should_evaluate?(targetable)
    trace_time("ruleset_should_evaluate", tags: ["target:#{target}", "enforcement:#{enforcement}", "source_type:#{source_type}"]) do
      bulk_filter_targetable([targetable]) == [targetable]
    end
  end

  sig do
    type_parameters(:T)
      .params(targetables: T::Enumerable[T.all(RuleEngine::Conditions::Targetable, T.type_parameter(:T))])
      .returns(T::Array[T.all(RuleEngine::Conditions::Targetable, T.type_parameter(:T))])
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
      relevant_targetables = targetables.filter { definition.target_supports_targetable?(_1) }.to_h do |targetable|
        [definition.redirect_condition_targetable(targetable), targetable]
      end

      parameters_by_condition = conditions.to_h { |condition| [condition.target, condition.parameters] }
      matching_targetables = RuleEngine::Conditions::Evaluator.evaluate(relevant_targetables.keys, parameters_by_condition)

      matching_targetables.map { |targetable| relevant_targetables[targetable] }.compact
    end
  end

  sig { returns(T::Array[RuleEngine::Conditions::ConditionTarget::TargetObject]) }
  def missing_condition_targets
    actual_condition_targets = conditions.map { |condition| condition.target_object }.sort
    required_condition_targets = definition.required_condition_targets.sort

    required_condition_targets - actual_condition_targets
  end

  sig do
    params(
      targetable: RuleEngine::Conditions::Targetable,
      target_object: RuleEngine::Conditions::ConditionTarget::TargetObject
    ).returns(T::Boolean)
  end
  def satisfies_conditions?(targetable, target_object)
    trace_time("ruleset_satisfies_conditions", tags: ["target:#{target}", "enforcement:#{enforcement}", "source_type:#{source_type}"]) do
      return false if conditions.none? || conditions.none? { |condition| condition.target_object == target_object }
      return false unless definition.target_supports_targetable?(targetable)

      condition = conditions.find { |condition| condition.target_object == target_object }
      return false unless condition

      RuleEngine::Conditions::Evaluator.evaluate([targetable], { condition.target => condition.parameters }).any?
    end
  end

  sig { params(new_conditions: T::Array[{ target: String, parameters: T.untyped }]).returns(T::Boolean) }
  def upsert_conditions(new_conditions)
    @conditions_added = []
    @conditions_updated = []
    @conditions_deleted = []

    existing_conditions_lookup = conditions.index_by { |condition| condition[:target] }
    new_conditions_lookup = T.let({}, T::Hash[String, { target: String, parameters: T.untyped }])

    new_conditions.map(&:deep_symbolize_keys).each do |condition_hash|
      key = condition_hash[:target].to_s
      new_conditions_lookup[key] = condition_hash

      if existing_conditions_lookup.key?(key)
        condition = T.must(existing_conditions_lookup[key])
        condition.parameters = condition_hash[:parameters] || {}

        next unless condition.changed?
        next if condition.changed_attributes.keys == ["parameters"] && Hashdiff.diff(condition.attributes[:parameters], condition.changed_attributes[:parameters]).empty?

        raise ConditionValidationError.new(condition, condition.parameter_errors) if !condition.valid? && condition.parameter_errors&.any?

        condition.save!

        @conditions_updated << condition
        next
      end

      condition = self.conditions.build(
        target: condition_hash[:target],
        parameters: condition_hash[:parameters] || {},
      )

      raise ConditionValidationError.new(condition, condition.parameter_errors) if !condition.valid? && condition.parameter_errors&.any?

      condition.save!

      @conditions_added << condition
    end

    existing_conditions_lookup.each do |key, condition|
      next if new_conditions_lookup.key?(key)

      self.conditions.destroy(condition)

      @conditions_deleted << condition
    end

    @conditions_added.any? || @conditions_updated.any? || @conditions_deleted.any?
  end

  sig { params(new_rules: T::Array[{ rule_type: String, parameters: T.untyped }], apply_default_parameters: T::Boolean, actor_id: T.nilable(Integer)).returns(T::Boolean) }
  def upsert_rules(new_rules, apply_default_parameters: false, actor_id: nil)
    @rules_added = []
    @rules_updated = []
    @rules_deleted = []

    existing_rules_lookup = rule_configurations.index_by(&:rule_type)
    new_rules_lookup = T.let({}, T::Hash[String, { rule_type: String, parameters: T.untyped }])

    new_rules.map(&:deep_symbolize_keys).each do |rule_hash|
      new_rules_lookup[rule_hash[:rule_type]] = rule_hash

      if existing_rules_lookup.key?(rule_hash[:rule_type])
        rule = T.must(existing_rules_lookup[rule_hash[:rule_type]])
        rule.parameters = apply_default_parameters ? apply_default_parameters(rule[:rule_type], rule_hash[:parameters] || {}) : rule_hash[:parameters]

        next unless rule.changed?
        next if rule.changed_attributes.keys == ["parameters"] && Hashdiff.diff(rule.attributes[:parameters], rule.changed_attributes[:parameters]).empty?

        rule.updated_by_id = actor_id || GitHub.context[:actor_id]

        raise RuleValidationError.new(rule.errors) unless rule.save

        @rules_updated << rule
        next
      end

      rule = self.rule_configurations.build(
        rule_type: rule_hash[:rule_type],
        parameters: apply_default_parameters ? apply_default_parameters(rule_hash[:rule_type], rule_hash[:parameters] || {}) : rule_hash[:parameters],
        created_by_id: actor_id || GitHub.context[:actor_id]
      )

      raise RuleValidationError.new(rule.errors) unless rule.save

      @rules_added << rule
    end

    existing_rules_lookup.each do |key, rule|
      next if new_rules_lookup.key?(key)

      self.rule_configurations.destroy(rule)

      @rules_deleted << rule
    end

    @rules_added.any? || @rules_updated.any? || @rules_deleted.any?
  end

  sig { params(new_bypass_actors: T::Array[{ actor_type: String, bypass_mode: T.nilable(T.any(Symbol, Integer)) }]).returns(T::Boolean) }
  def upsert_bypass_actors(new_bypass_actors)
    RepositoryRulesetBypassActor.upsert_bypass_actors(self, new_bypass_actors)
  end

  sig { void }
  def append_history
    return unless source.rules_history?

    updated_by_id = GitHub.context[:actor_id] || User.ghost

    self.rule_configurations.reload
    self.conditions.reload
    self.bypass_actors.reload

    state = self.serialize

    self.histories.create(
      state:,
      updated_by_id:,
    )
  end

  batch_method(:latest_history_id, T.nilable(Integer)) do |rulesets|
    latest_histories = RepositoryRulesetHistory.where(repository_ruleset_id: rulesets.map(&:id))
    .pluck(:id, :repository_ruleset_id, :created_at)
    .reduce({}) do |acc, (id, repository_ruleset_id, created_at)|
      acc[repository_ruleset_id] ||= []
      acc[repository_ruleset_id] << { id: id, created_at: created_at }
      acc
    end.map do |repository_ruleset_id, histories|
      [repository_ruleset_id, histories.max_by { |history| history[:created_at] }[:id]]
    end.to_h

    rulesets.index_with { |ruleset| latest_histories[ruleset.id] }
  end

  sig { returns(RuleEngine::RuleProviders::RulesetRuleProvider) }
  def rule_provider
    if targets_push?
      T.cast(RuleEngine::Evaluator::RULE_PROVIDERS.find { |rp| rp.identifier == "push_ruleset" }, RuleEngine::RuleProviders::RulesetRuleProvider)
    elsif targets_repository?
      T.cast(RuleEngine::Evaluator::RULE_PROVIDERS.find { |rp| rp.identifier == "repository_policy" }, RuleEngine::RuleProviders::RulesetRuleProvider)
    else
      T.cast(RuleEngine::Evaluator::RULE_PROVIDERS.find { |rp| rp.identifier == "ref_ruleset" }, RuleEngine::RuleProviders::RulesetRuleProvider)
    end
  end

  class ConditionValidationError < StandardError
    attr_reader :errors, :parameter_instance

    def initialize(parameter_instance, errors)
      @parameter_instance = parameter_instance
      @errors = errors
    end

    def parse_error_messages
      pattern_errors, other_errors = errors.partition { |error| error[:error_code] == :invalid && error[:sub_errors]&.any? { |sub_error| sub_error[:error_code] == :invalid_pattern } }
      failed_patterns = pattern_errors.flat_map do |error|
        error[:sub_errors].filter_map do |sub_error|
          next unless sub_error[:error_code] == :invalid_pattern
          sub_error[:value]
        end
      end
      messages = other_errors.flat_map { |error| error[:message] }.compact
      messages << "Invalid target patterns: \'#{failed_patterns.uniq.join("\', \'")}\'" if failed_patterns.present?
      messages
    end
  end

  class RuleValidationError < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
    end
  end

  class BypassActorsLimitError < StandardError
    MESSAGE = "The ruleset bypass actor limit has been reached."

    def message
      MESSAGE
    end
  end

  class BypassActorsValidationError < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
    end
  end

  class InvalidTarget < StandardError
    attr_reader :message

    def initialize(target)
      @message = "'#{target}' is not a valid target"
    end
  end

  class InvalidSource < StandardError
    attr_reader :message

    def initialize(source)
      @message = "'#{source}' is not a valid source"
    end
  end

  # A general error class we can use to rescue ruleset specific errors
  class Error < StandardError
    attr_reader :message

    def initialize(message)
      @message = message
    end
  end

  def event_payload
    payload = {
      ruleset_id: id,
      ruleset_name: name,
      ruleset_enforcement: enforcement,
    }
    payload.merge!(definition.event_payload)
    payload
  end

  def changes_payload(include_deleted_models: false)
    payload = {}

    AUDITABLE_FIELDS.each do |field|
      payload["ruleset_old_#{field}".to_sym] = attribute_before_last_save(field) if saved_change_to_attribute?(field)
    end

    if @rules_added&.any?
      payload.merge!(ruleset_rules_added: @rules_added.map(&:event_payload))
    end

    if @rules_updated&.any?
      payload.merge!(ruleset_rules_updated: @rules_updated.map { |r| r.changes_payload.merge!(r.event_payload) })
    end

    if @rules_deleted&.any?
      payload.merge!(ruleset_rules_deleted: @rules_deleted.map(&:event_payload))
    end

    if @conditions_added&.any?
      payload.merge!(ruleset_conditions_added: @conditions_added.map(&:event_payload))
    end

    if @conditions_updated&.any?
      payload.merge!(ruleset_conditions_updated: @conditions_updated.map { |c| c.changes_payload.merge!(c.event_payload) })
    end

    if @conditions_deleted&.any?
      payload.merge!(ruleset_conditions_deleted: @conditions_deleted.map(&:event_payload))
    end

    if @bypass_actors_added&.any?
      payload.merge!(ruleset_bypass_actors_added: @bypass_actors_added.map(&:event_payload))
    end

    if @bypass_actors_updated&.any?
      payload.merge!(ruleset_bypass_actors_updated: @bypass_actors_updated.map(&:event_payload))
    end

    if @bypass_actors_deleted&.any?
      payload.merge!(ruleset_bypass_actors_deleted: @bypass_actors_deleted.map(&:event_payload))
    end

    if include_deleted_models
      payload[:deleted_rules] = @rules_deleted if @rules_deleted
      payload[:deleted_conditions] = @conditions_deleted if @conditions_deleted
    end

    payload
  end

  def apply_default_parameters(rule_type, parameters)
    parameters = parameters.deep_stringify_keys
    impl = RuleEngine::Evaluator.rule_impl_for_rule_type(rule_type)
    return parameters if impl.nil?

    impl.parameter_schema.apply_defaults_for_source(source, parameters)
    parameters
  end

  # Use return the source node if set
  # otherwise, return the source of the ruleset
  def async_source_node
    async_source.then do |source|
      next source_node if source_node.present?
      source
    end
  end

  # URL for this ruleset.
  #
  # source_view - The source from which to view the ruleset (defaults to the ruleset's source).
  #               Use this to render the appropriate url for a ruleset or
  #               inherited ruleset depending on where it's being viewed from.
  #               If the ruleset doesn't exist for the provided source or
  #               the user doesn't have access to the source,
  #               the url should result in a 404.
  sig do
    params(
      source_view: RuleEngine::Types::RuleSource
    ).returns(T.nilable(String))
  end
  def url(source_view: source)
    # There is currently no readonly html url for repository policies at the repository level
    target == "repository" && source_view.is_a?(Repository) ? nil : RulesetDefinitions::RulesetDefinition.factory(source_view, nil, target).url(id)
  end

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
        bypass_actors: {
          only: [
            :type,
            :id,
            :actor_id,
            :actor_type,
            :bypass_mode,
          ],
          root: false
        },
      ], root: false
    )

    serialized.to_json
  end

  sig { params(allow_upsell: T::Boolean).returns(T::Array[String]) }
  def available_rule_types(allow_upsell: false)
    @available_rule_types ||= {}
    @available_rule_types[allow_upsell] ||= RuleEngine::Evaluator::REGISTERED_RULES.filter_map do |_, rule|
      next unless rule.is_user_configurable?(source) &&
        rule.is_feature_enabled?(source) &&
        rule.is_supported_by_source_type?(source) &&
        rule.is_supported_by_plan?(source, allow_upsell:) &&
        rule.is_supported_by_target?(target)
      rule.rule_name
    end
  end

  sig { returns(T.nilable(Business)) }
  memoize def business
    return unless self.present?
    source = T.must(self).source
    return unless source.present?

    if source.is_a?(Business)
      source
    elsif source.is_a?(Organization)
      source.business
    elsif source.is_a?(Repository)
      return unless source.owner.present?
      if source.emu_user_owned?
        source.enterprise_managed_business
      else
        # don't user source.business because if this is an org-owned fork network, we'll get that org's business
        source.async_business.sync
      end
    else
      nil
    end
  end

  sig { returns(T.nilable(Organization)) }
  memoize def organization
    return unless self.present?
    source = T.must(self).source

    org = T.let(nil, T.nilable(Organization))
    if source.is_a?(Organization)
      org = source
    elsif source.is_a?(Repository) && source.owner.is_a?(Organization)
      org = T.cast(source.owner, Organization)
    end
    org
  end

  sig { returns(T::Boolean) }
  def supports_delegated_bypass?
    bypass_actors.any?
  end

  sig { params(actor: RuleEngine::Types::Actor, repository: Repository).returns(T::Boolean) }
  def matches_bypassers?(actor, repository)
    rule_provider.ruleset_bypass_allowed?(self, actor, repository, is_pull_request: false)
  end

  sig { params(repository: Repository).returns(T::Array[Integer]) }
  def bypassable_user_ids(repository)
    RepositoryRulesetBypassActor.matching_user_ids(repository, bypass_actors.to_a)
  end

  private

  def instrument_create
    payload = {}.tap do |payload|
      payload[:ruleset_rules] = @rules_added.map(&:event_payload) if @rules_added
      payload[:ruleset_conditions] = @conditions_added.map(&:event_payload) if @conditions_added
      payload[:ruleset_bypass_actors] = self.bypass_actors.map(&:event_payload)
    end

    instrument :create, payload
  end

  def instrument_update
    payload = changes_payload

    instrument :update, payload if payload.any?
  end

  def instrument_destroy
    payload = {}.tap do |payload|
      payload[:ruleset_rules] = rule_configurations.map(&:event_payload) if rule_configurations.any?
      payload[:ruleset_conditions] = conditions.map(&:event_payload) if conditions.any?
      payload[:ruleset_bypass_actors] = bypass_actors.map(&:event_payload) if bypass_actors.any?
    end

    instrument :destroy, payload
  end

  def generate_deleted_webhook_payload
    event = construct_webhook_event(:deleted)
    @delivery_system = Hook::DeliverySystem.new(event)
    @delivery_system.generate_hookshot_payloads
  end

  def queue_webhook_delivery
    raise "'generate_deleted_webhook_payload' must be called before `queue_webhook_delivery'" unless defined?(@delivery_system)

    @delivery_system&.deliver_later
  end

  def queue_update_webhook_delivery
    return unless changes_payload.any?

    @update_webhook_event = construct_webhook_event(:edited)

    @delivery_system = Hook::DeliverySystem.new(@update_webhook_event)
    @delivery_system.generate_hookshot_payloads
    @delivery_system.deliver_later
  end

  def construct_webhook_event(action)
    Hook::Event::RepositoryRulesetEvent.new(
      action: action,
      repository_ruleset_id: id,
      actor_id: GitHub.context[:actor_id],
      changes: webhook_needs_changes?(action) ? changes_payload(include_deleted_models: true) : nil,
      triggered_at: Time.now
    )
  end

  def webhook_needs_changes?(action)
    action == :edited
  end

  def ensure_valid_plan
    unless !evaluate? || definition.supports_evaluate_mode?
      errors.add(:enforcement, "evaluate option is not supported on this plan. Please upgrade to Enterprise to enable it.")
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

  def ensure_ruleset_limit_not_exceeded
    if RepositoryRuleset.limit_reached?(source)
      errors.add(:base, "The ruleset limit of #{RepositoryRuleset.ruleset_limit_count(source)} has been reached.")
    end
  end

  def bypass_actors_valid
    return unless source.present?

    RepositoryRulesetBypassActor.validate_all_associations(bypass_actors.to_a, self)
    valid_actors = bypass_actors.filter { |actor| actor.errors.empty? }
    has_invalid_bypass_actors = valid_actors.length != bypass_actors.length
    errors.add(:bypass_actors, "must be GitHub Apps, roles, or public teams associated with the ruleset source.") if has_invalid_bypass_actors

    # some types of bypass actors can only have one per ruleset.
    # it's hard to enforce that at the bypass actor level, so do it here
    groups = bypass_actors.group_by(&:type)
    groups.each do |type, bypassers_by_type|
      klass = type.constantize
      klass.validate_bypass_actors(self, bypassers_by_type)
    end
  end

  def reconcile_merge_queues
    definition.reconcile_merge_queues
  end
end
