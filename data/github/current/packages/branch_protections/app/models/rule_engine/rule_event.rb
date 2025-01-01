# typed: strict
# frozen_string_literal: true

module RuleEngine
  class RuleEvent
    extend T::Sig
    extend T::Helpers

    include Conditions::Targetable

    abstract!

    # Represents a discrete action taken as part of this event
    # Events must have at least one action but may have more
    # For example, a push contains many ref updates, each of which is an action
    # Add new actions using the Sorbet format; # T.any(Git::Ref::Update, ...)
    EventAction = T.type_alias { T.any(Git::Ref::Update, Events::RepositoryOperationEvent::Operation) }

    sig { returns(Types::Actor) }
    attr_reader :actor

    sig { params(actor: Types::Actor).void }
    def initialize(actor)
      @actor = actor
    end

    sig { overridable.params(rule_configs: T::Array[RepositoryRuleConfiguration]).void }
    def before_evaluation(rule_configs); end

    sig { abstract.returns(T::Array[EventAction]) }
    def event_actions; end

    sig { abstract.params(rule_suites: T::Array[RuleSuite]).returns(T::Array[RuleSuite]) }
    def finalize_rule_suites(rule_suites); end

    sig { overridable.params(rule_suites: T::Array[RuleSuite]).void }
    def record_results(rule_suites); end

    sig { overridable.params(exception: StandardError).returns(T::Array[RuleSuite]) }
    def handle_exception(exception)
      raise exception
    end
  end
end
