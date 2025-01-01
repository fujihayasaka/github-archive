# typed: true
# frozen_string_literal: true

module RuleEngine
  class RuleProvider
    extend T::Helpers
    extend T::Sig
    abstract!

    sig { returns(String) }
    attr_reader :identifier

    sig { params(identifier: String).void }
    def initialize(identifier:)
      @identifier = identifier
    end

    # Called during evaluation to discover the rules that apply to the given event
    # event - A RuleEvent
    #
    # Returns an array of RepositoryRuleConfigurations
    sig { abstract.params(event: RuleEvent).returns(T::Array[RepositoryRuleConfiguration]) }
    def rules_for_event(event); end

    sig do
      abstract.params(
        rule_config: RepositoryRuleConfiguration,
        actor: Types::Actor,
        repository: Repository,
        rule_run: T.nilable(RuleRun)
      ).returns(T::Boolean)
    end
    def can_bypass?(rule_config, actor, repository, rule_run = nil); end

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
