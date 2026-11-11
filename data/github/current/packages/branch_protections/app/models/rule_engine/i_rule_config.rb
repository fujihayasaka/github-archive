# typed: strict
# frozen_string_literal: true

module RuleEngine
  # Abstract interface for rule configuration objects used by the rule engine.
  module IRuleConfig
    extend T::Helpers

    requires_ancestor { Object }

    abstract!

    # Returns the database ID of this config, or nil if not persisted
    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    # Returns the rule type string (e.g. "pull_request", "required_status_checks")
    sig { abstract.returns(String) }
    def rule_type; end

    # Returns the raw parameters hash for this rule configuration
    sig { abstract.returns(T::Hash[String, T.untyped]) }
    def parameters; end

    # Returns the value of a specific parameter by name
    sig { abstract.params(parameter_name: String).returns(T.untyped) }
    def param(parameter_name); end

    # Returns whether a parameter exists by name
    sig { abstract.params(parameter_name: String).returns(T::Boolean) }
    def has_param(parameter_name); end # rubocop:disable Naming/PredicatePrefix

    # Returns the identifier string of the provider backing this config
    sig { abstract.returns(String) }
    def provider_name; end

    # Returns the RuleProvider that backs this config
    sig { abstract.returns(RuleEngine::RuleProvider) }
    def provider; end

    # Returns the ID of the provider backing this config
    sig { abstract.returns(T.nilable(Integer)) }
    def provider_id; end

    # Returns the history ID for this config
    # Used for providers that maintain history of changes to rule configurations
    sig { abstract.returns(T.nilable(Integer)) }
    def history_id; end

    # Returns the source of this rule (e.g. Enterprise, Organization, Repository)
    sig { abstract.returns(T.untyped) }
    def source; end

    # Returns whether this config is in evaluate (non-enforcing) mode
    sig { abstract.returns(T::Boolean) }
    def evaluate_mode?; end

    # Returns whether this config is enabled
    sig { abstract.returns(T::Boolean) }
    def enabled?; end

    sig { returns(T.nilable(RuleEngine::BaseRule)) }
    def evaluator
      RuleEngine::Evaluator.rule_impl_for_rule_type(rule_type)
    end

    sig { params(actor: T.nilable(RuleEngine::Types::Actor), targetable: Targeting::Targetable).returns(T::Boolean) }
    def can_bypass?(actor, targetable)
      return false unless actor
      provider.can_bypass?(self, actor, targetable)
    end

    sig { params(actor: T.nilable(RuleEngine::Types::Actor), targetable: Targeting::Targetable).returns(T::Boolean) }
    def can_skip?(actor, targetable)
      return false unless actor
      provider.can_skip?(self, actor, targetable)
    end

    # === Targeting attributes and methods ===
    # These methods will be removed once the providers handle targeting logic

    # Returns the ref names this rule matches
    sig { abstract.returns(T.nilable(T::Array[String])) }
    def matching_ref_names; end

    # Sets the ref names this rule matches
    sig { abstract.params(ref_names: T.nilable(T::Array[String])).void }
    def matching_ref_names=(ref_names); end

    # Returns the event actions this rule matches
    sig { abstract.returns(T.nilable(T::Array[RuleEngine::RuleEvent::EventAction])) }
    def matching_event_actions; end

    # Sets the event actions this rule matches
    sig { abstract.params(actions: T.nilable(T::Array[RuleEngine::RuleEvent::EventAction])).void }
    def matching_event_actions=(actions); end

    sig { params(ref_name: String).returns(T::Boolean) }
    def provider_rule_matches_ref?(ref_name)
      matching_ref_names&.include?(ref_name) || false
    end

    sig { params(action: RuleEngine::RuleEvent::EventAction).returns(T::Boolean) }
    def provider_rule_matches_action?(action)
      matching_event_actions&.include?(action) || false
    end
  end
end
