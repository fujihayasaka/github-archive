# typed: true
# frozen_string_literal: true

module RuleEngine
  class RuleProvider
    extend T::Helpers
    abstract!

    sig { returns(String) }
    attr_reader :identifier

    sig { params(identifier: String).void }
    def initialize(identifier:)
      @identifier = identifier
    end

    # TODO: This should call `rules_for_targetables` by default and allow
    # subclasses to override it if they want to use event-specific data like the User
    #
    # Called during evaluation to discover the rules that apply to the given event
    # event - A RuleEvent
    #
    # Returns an array of RepositoryRuleConfigurations
    sig { abstract.params(event: RuleEvent).returns(T::Array[RepositoryRuleConfiguration]) }
    def rules_for_event(event); end

    # Called during evaluation or rule inspection to discover the rules that apply to the given targetable resources.
    # targetables - A array of Targetable objects
    #
    # Returns a hash of targetable => array of RepositoryRuleConfigurations that apply to that targetable
    sig { abstract.params(targetables: T::Enumerable[Conditions::Targetable]).returns(T::Hash[Conditions::Targetable, T::Array[RepositoryRuleConfiguration]]) }
    def rules_for_targetables(targetables); end

    sig do
      abstract.params(
        rule_config: RepositoryRuleConfiguration,
        actor: Types::Actor,
        targetable: Conditions::Targetable,
        rule_run: T.nilable(RuleRun)
      ).returns(T::Boolean)
    end
    def can_bypass?(rule_config, actor, targetable, rule_run = nil); end

    # Called after evaluation of all rules and bypass is completed
    # RuleSuite has been persisted to the database (for ruleset rules)
    sig do
      overridable.params(
        rule_suite: RuleSuite,
        event: RuleEvent,
      ).void
    end
    def on_evaluation_complete(rule_suite, event)
    end

    sig { overridable.params(rule_run: RuleRun).returns(T.nilable(String)) }
    def insights_category(rule_run)
      "System rules" unless rule_run.allowed?
    end

  end
end
