# typed: true
# frozen_string_literal: true

class RepositoryRuleset < ApplicationRecord::Repositories
  include Instrumentation::Model
  include GitHub::Memoizer
  include GitHub::BatchMethod
  include RuleEngine::Timing
  extend RuleEngine::Timing
  include RuleEngine::IRuleset

  sig { returns(RuleEngine::RulesetImplementationPayload) }
  def self.impl_payload
    RuleEngine::RulesetImplementationPayload.new(
      ruleset_class: "RepositoryRuleset",
      rule_condition_class: "RepositoryRuleCondition",
      rule_configuration_class: "RepositoryRuleConfiguration",
      ruleset_history_class: "RepositoryRulesetHistory",
      ruleset_bypass_actor_class: "RepositoryRulesetBypassActor",
      ruleset_association_name: "repository_ruleset"
    )
  end
  include RuleEngine::RulesetBase

  after_commit :append_history, on: [:create, :update]
  after_commit :cancel_bypass_requests, on: [:update]

  validates_uniqueness_of :name, scope: [:source], case_sensitive: false, message: "must be unique"
  before_validation :strip_whitespace
  validates_presence_of :name, message: "cannot be empty"
  validates_presence_of :source

  enum :target, { branch: 0, tag: 1, push: 2, repository: 3, actions: 4 }, prefix: :targets

  destroy_in_background_with :source, polymorphic_class_name: "Repository"

  AUDITABLE_FIELDS = %i[enforcement name].freeze

  validate :bypass_actors_valid

  enum :enforcement, { disabled: 0, enabled: 1, evaluate: 2 }
  scope :not_disabled, -> { where.not(enforcement: :disabled) }
  scope :not_enabled, -> { where.not(enforcement: :enabled) }

  # Primarily used in the graphql context
  # Set the node from which we are requesting rulesets to properly determine
  # if the viewer has access to rulesets within this context
  sig { returns(T.nilable(RuleEngine::Types::RuleSource)) }
  attr_accessor :source_node

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

  def strip_whitespace
    self[:name] = self[:name]&.strip
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

      source_rulesets = Repositories.domain.rulesets.load_rulesets(source_repo, include_inherited: false, targets: targets)
      source_rulesets = source_rulesets.select(&:enabled?)
      source_rulesets = T.cast(source_rulesets, T::Array[RepositoryRuleset])

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

  sig { override.params(new_bypass_actors: T::Array[{ actor_type: String, bypass_mode: T.nilable(T.any(Symbol, Integer)) }]).returns(T::Boolean) }
  def upsert_bypass_actors(new_bypass_actors)
    return false unless definition.supports_bypass?

    was_changed = RepositoryRulesetBypassActor.upsert_bypass_actors(self, new_bypass_actors)
    if persisted? && was_changed
      touch_later
    end
    was_changed
  end

  sig { void }
  def cancel_bypass_requests
    return unless source&.feature_flag_enabled?(:repo_policy_bypass, default: false)

    if targets_push?
      rule_provider = "push_ruleset"
    elsif targets_repository?
      rule_provider = "repository_policy"
    else
      # ref rulesets don't support bypass requests
      return
    end

    CancelPendingExemptionRequestsJob.perform_later(self, rule_provider)
  end

  sig { override.returns(RuleEngine::RuleProviders::RulesetRuleProvider) }
  def rule_provider
    if targets_push?
      T.cast(domain.registry.rule_providers.find { |rp| rp.identifier == "push_ruleset" }, RuleEngine::RuleProviders::RulesetRuleProvider)
    elsif targets_repository?
      T.cast(domain.registry.rule_providers.find { |rp| rp.identifier == "repository_policy" }, RuleEngine::RuleProviders::RulesetRuleProvider)
    else
      T.cast(domain.registry.rule_providers.find { |rp| rp.identifier == "ref_ruleset" }, RuleEngine::RuleProviders::RulesetRuleProvider)
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
    impl = domain.registry.rule_impl_for_rule_type(rule_type)
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

  SERIALIZATION_ASSOCIATIONS = DEFAULT_SERAILIZATION_ASSOCIATIONS.merge({
    bypass_actors: {
      only: [
        :type,
        :id,
        :actor_id,
        :actor_type,
        :bypass_mode,
      ],
      root: false
    }
  })

  sig { override.returns(String) }
  def serialize
    self.as_json(only: DEFAULT_SERIALIZATION_FIELDS, include: SERIALIZATION_ASSOCIATIONS, root: false).to_json
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
    rule_provider.ruleset_bypass_allowed?(self, actor, Targeting::Targets::Repository.new(repository:), is_pull_request: false)
  end

  sig { params(repository: Repository).returns(T::Array[Integer]) }
  def bypassable_user_ids(repository)
    RepositoryRulesetBypassActor.matching_user_ids(repository, bypass_actors.to_a)
  end

  sig { override.returns(RuleEngine::DomainAccessorBase[RuleEngine::Types::RuleSource]) }
  def domain
    Repositories.domain.rulesets
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

  def bypass_actors_valid
    return unless source.present?

    RepositoryRulesetBypassActor.validate_all_associations(bypass_actors.to_a, self)
    valid_actors, invalid_actors = bypass_actors.partition { |actor| actor.errors.empty? }
    if invalid_actors.any?
      if source.is_a?(Repository)
        valid_actor_types = "GitHub Apps, organization roles, public teams, or users"
      else
        valid_actor_types = "GitHub Apps, organization roles, or public teams"
      end
      errors.add(:bypass_actors, "must be either #{valid_actor_types} that are linked to the ruleset source. The following actor(s) are invalid: #{invalid_actors.map { |actor| actor.actor&.name }.join(", ")}")
    end

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
