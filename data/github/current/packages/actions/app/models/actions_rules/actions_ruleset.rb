# typed: true
# frozen_string_literal: true

require "hashdiff"

module ActionsRules
  class ActionsRuleset < ApplicationRecord::ActionsEnvironments
    include GitHub::Memoizer
    include RuleEngine::Timing
    extend RuleEngine::Timing
    include RuleEngine::IRuleset

    sig { returns(RuleEngine::RulesetImplementationPayload) }
    def self.impl_payload
      RuleEngine::RulesetImplementationPayload.new(
        ruleset_class: "ActionsRules::ActionsRuleset",
        rule_condition_class: "ActionsRules::ActionsRuleCondition",
        rule_configuration_class: "ActionsRules::ActionsRuleConfiguration",
        ruleset_history_class: "ActionsRules::ActionsRulesetHistory",
        ruleset_bypass_actor_class: nil,
        ruleset_association_name: "actions_ruleset"
      )
    end
    include RuleEngine::RulesetBase

    self.table_name = "actions_rulesets"

    after_commit :append_history, on: [:create, :update]

    validates_uniqueness_of :name, scope: [:source], case_sensitive: false, message: "must be unique"
    before_validation :strip_whitespace
    validates_presence_of :name, message: "cannot be empty"
    validates_presence_of :source

    # Actions rulesets only support the "actions" target
    enum :target, { actions: 0 }, prefix: :targets

    enum :enforcement, { disabled: 0, enabled: 1, evaluate: 2 }
    scope :not_disabled, -> { where.not(enforcement: :disabled) }
    scope :not_enabled, -> { where.not(enforcement: :enabled) }

    def strip_whitespace
      self[:name] = self[:name]&.strip
    end

    sig { override.returns(String) }
    def serialize
      self.as_json(only: DEFAULT_SERIALIZATION_FIELDS, include: DEFAULT_SERAILIZATION_ASSOCIATIONS, root: false).to_json
    end

    sig { override.returns(RuleEngine::RuleProviders::RulesetRuleProvider) }
    def rule_provider
      T.cast(
        T.must(domain.registry.rule_providers.find { |rp| rp.identifier == "actions_ruleset" }),
        RuleEngine::RuleProviders::RulesetRuleProvider,
      )
    end

    sig { override.returns(T::Enumerable[T.untyped]) }
    def bypass_actors
      []
    end

    sig { override.returns(RuleEngine::DomainAccessorBase[RuleEngine::Types::RuleSource]) }
    def domain
      Actions.domain.rulesets
    end
  end
end
